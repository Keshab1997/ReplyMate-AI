package com.keshabstudios.replymate

import android.content.Intent
import android.os.Bundle
import android.app.RemoteInput
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * The MVP's only message-context source: notifications the user chose to share.
 *
 * Rules this service lives by (docs/NOTIFICATION_LISTENER.md,
 * docs/PRIVACY_AND_PERMISSIONS.md):
 *  - Processes only packages the user selected on the app-selection screen.
 *  - Never retains message content: events are forwarded once and forgotten;
 *    the only thing kept is the last notification that exposed a reply action,
 *    so a quick reply has something to act on while it is still valid.
 *  - Quick reply is attempted only when a valid RemoteInput action exists;
 *    every failure returns false and the Flutter side offers copy / open-app.
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
    }

    /** Most recent notification that exposed a RemoteInput reply action. */
    private var lastReplyable: StatusBarNotification? = null

    override fun onListenerConnected() {
        instance = this
        emit(mapOf("type" to "listener_connected"))
    }

    override fun onListenerDisconnected() {
        instance = null
        lastReplyable = null
        emit(mapOf("type" to "listener_disconnected"))
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (!isAllowed(sbn.packageName)) return
        val parsed = NotificationParser.parse(sbn)
        if (parsed["hasReplyAction"] == true) {
            lastReplyable = sbn
        }
        emit(mapOf("type" to "notification_captured", "notification" to parsed))
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        if (sbn != null && sbn.key == lastReplyable?.key) {
            // A dismissed notification's reply action is gone; never fire at it.
            lastReplyable = null
        }
    }

    private fun isAllowed(packageName: String): Boolean {
        val allowed =
            getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                .getStringSet(KEY_ALLOWED_PACKAGES, emptySet()) ?: emptySet()
        return allowed.contains(packageName)
    }

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

    private fun emit(event: Map<String, Any?>) {
        eventSink?.invoke(event)
    }
}
