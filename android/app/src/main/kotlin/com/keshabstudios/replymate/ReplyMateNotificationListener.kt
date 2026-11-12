package com.keshabstudios.replymate

import android.app.Notification
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.app.RemoteInput
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification


/**
 * The MVP's only message-context source: notifications the user chose to share.
 *
 * Rules this service lives by.md,
 * md):
 *  - Processes only packages the user selected on the app-selection screen.
 *  - Never retains message content: events are forwarded once and forgotten;
 *    the only things kept are the last notification that exposed a reply
 *    action (so a quick reply has something to act on while it is still valid)
 *    and the pending overlay context, which lives in memory in
 *    [OverlayBubbleController] and is cleared when the panel reads it.
 *  - Quick reply is attempted only when a valid RemoteInput action exists;
 *    every failure returns false and the Flutter side offers copy / open-app.
 *
 * Since the floating bubble exists.md) this service also
 * decides, per notification, whether the bubble is raised or the fallback
 * notification is posted. That decision is `routeToOverlay` below; the filter
 * it applies is.md §5.3.
 */
class ReplyMateNotificationListener : NotificationListenerService() {

    companion object {
        @Volatile
        var instance: ReplyMateNotificationListener? = null
            private set

        /**
         * Installed by MainActivity once the platform channel exists. Events
         * posted before that (or after the engine is torn down) are dropped on
         * purpose: nothing may be queued, because queued message content would
         * be retained message content.
         */
        @Volatile
        var eventSink: ((Map<String, Any?>) -> Unit)? = null

        const val PREFS_NAME = "replymate_native"
        const val KEY_ALLOWED_PACKAGES = "allowed_packages"

        /**
         * How long the bubble survives its notification being retracted. Long
         * enough for a finger already moving towards it, short enough that a
         * genuinely dismissed message does not linger
         * md §5.3).
         */
        private const val BUBBLE_RETRACTION_GRACE_MILLIS = 6_000L
    }

    /** Most recent notification that exposed a reply action. */
    private var lastReplyable: StatusBarNotification? = null

    private val handler = Handler(Looper.getMainLooper())

    /**
     * A bubble retraction waiting out its grace window. Kept so a new message
     * (or a re-post of the same one) can cancel it.
     */
    private var retractBubble: Runnable? = null

    override fun onListenerConnected() {
        instance = this
        emit(mapOf("type" to "listener_connected"))
    }

    override fun onListenerDisconnected() {
        instance = null
        lastReplyable = null
        cancelScheduledRetraction()
        emit(mapOf("type" to "listener_disconnected"))
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (!AppAllowlist.contains(this, sbn.packageName)) return
        val parsed = NotificationParser.parse(sbn)
        if (parsed["hasReplyAction"] == true) {
            lastReplyable = sbn
        }
        emit(mapOf("type" to "notification_captured", "notification" to parsed))
        cancelScheduledRetraction()
        routeToOverlay(sbn, parsed)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (sbn.key == lastReplyable?.key) {
            // A dismissed notification's reply action is gone; never fire at it.
            lastReplyable = null
        }
        // The bubble belongs to exactly one notification, so when that one goes
        // the bubble usually goes with it - but not instantly. Some apps
        // (WhatsApp, for the chat you already have open) post a notification
        // and retract it a moment later; clearing immediately made the bubble
        // flicker out before a finger could reach it. A short grace window
        // keeps it tappable, and a tap that is too late is still honest: the
        // panel says the reply action is no longer valid.
        if (sbn.key == OverlayBubbleController.pendingKey()) {
            scheduleBubbleRetraction(sbn.key)
        }
    }

    /** Retracts the bubble for [key] after the grace window, unless it was replaced. */
    private fun scheduleBubbleRetraction(key: String) {
        cancelScheduledRetraction()
        val task = Runnable {
            retractBubble = null
            if (OverlayBubbleController.pendingKey() == key) {
                // The notification is gone because the user opened the chat (or
                // the app withdrew it). Killing the bubble made it vanish the
                // moment a conversation was opened, which is when it is most
                // useful; instead it tucks itself against the screen edge and
                // waits to be tapped. It is the auto-hide timer - not the
                // notification - that eventually removes it.
                OverlayBubbleService.tuckAway(this)
            }
        }
        retractBubble = task
        handler.postDelayed(task, BUBBLE_RETRACTION_GRACE_MILLIS)
    }

    private fun cancelScheduledRetraction() {
        retractBubble?.let { handler.removeCallbacks(it) }
        retractBubble = null
    }

    // ------------------------------------------------------------- overlay

    /**
     * Decides whether this notification earns the bubble, and hands it to the
     * router that both message sources share.
     *
     * The content filters here are about *notifications* (ongoing, group
     * summaries, media controls); the "can we draw, and what if we cannot"
     * half of the decision lives in [OverlayRouter], because the screen reader
     * reaches the same question from a different direction and must get the
     * same answer.md §5.3).
     */
    private fun routeToOverlay(sbn: StatusBarNotification, parsed: Map<String, Any?>) {
        if (!qualifiesForBubble(sbn, parsed)) return
        OverlayRouter.route(this, parsed)
    }

    /**
     * The.md §5.3 filter: has text, is not a group
     * summary, is not ongoing, and is not a media transport. The allowlist is
     * checked by the caller and the user's switch by the router.
     */
    private fun qualifiesForBubble(
        sbn: StatusBarNotification,
        parsed: Map<String, Any?>,
    ): Boolean {
        val notification = sbn.notification ?: return false
        val text = parsed["text"] as? String
        if (text.isNullOrBlank()) return false
        if (parsed["isGroupSummary"] == true) return false
        if ((notification.flags and Notification.FLAG_ONGOING_EVENT) != 0) return false
        return !isMediaTransport(notification)
    }

    /**
     * Media/transport controls can carry text (a track name), and drawing a
     * reply bubble over Spotify would be nonsense. `MediaStyle` is exposed as a
     * template string; there is no public API for it.
     */
    private fun isMediaTransport(notification: Notification): Boolean {
        val template = notification.extras?.getString(Notification.EXTRA_TEMPLATE)
        return template?.contains("MediaStyle") == true
    }

    // ---------------------------------------------------------- quick reply

    /**
     * Attempts a RemoteInput quick reply against the last replyable
     * notification. Returns false when there is no live service, no stored
     * notification, no valid action, the stored notification is not the one
     * the user is replying to, or the send throws - the caller then shows the
     * documented copy / open-app fallback instead.
     *
     * [key] is the StatusBarNotification.key of the notification the reply
     * belongs to, and it must match the stored one. While the user reads one
     * conversation, a newer notification from another chat must never take
     * the reply with it: the user's words have to land in the chat they are
     * looking at, or nowhere at all.
     */
    fun sendQuickReply(text: String, key: String?): Boolean {
        if (text.isBlank()) return false
        if (key.isNullOrBlank()) return false
        val sbn = lastReplyable ?: return false
        // The reply belongs to exactly one notification. If a newer one has
        // been captured since, this action is stale - refuse it instead of
        // sending the user's reply into a conversation they are not reading.
        if (sbn.key != key) return false
        val action = sbn.notification.actions?.firstOrNull { candidate ->
            !(candidate?.remoteInputs.isNullOrEmpty())
        } ?: return false
        val remoteInput = action.remoteInputs?.firstOrNull() ?: return false
        return try {
            // Direct-reply wire format: the typed text goes into a bundle keyed
            // by the RemoteInput's result key, carried as EXTRA_RESULTS_DATA.
            val results = Bundle().apply {
                putCharSequence(remoteInput.resultKey, text)
            }
            val replyIntent = Intent().apply {
                putExtra(RemoteInput.EXTRA_RESULTS_DATA, results)
            }
            action.actionIntent.send(this, 0, replyIntent)
            lastReplyable = null
            true
        } catch (t: Throwable) {
            // IntentSender.sendIntent throws IntentSender.SendIntentException
            // when the action is dead; anything else is equally a "no".
            false
        }
    }

    /** Releases the retained notification when the reply-composer session ends. */
    fun clearRetainedReplyAction() {
        lastReplyable = null
    }

    private fun emit(event: Map<String, Any?>) {
        eventSink?.invoke(event)
    }
}
