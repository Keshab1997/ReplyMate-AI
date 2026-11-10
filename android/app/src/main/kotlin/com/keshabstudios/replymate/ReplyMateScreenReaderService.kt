package com.keshabstudios.replymate

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent

/**
 * The second message source: the screen itself.
 *
 * A messaging app posts no notification for the conversation the user is
 * already looking at, so the notification listener sees nothing exactly when
 * the user is most likely to want a reply. This service closes that gap by
 * reading the visible conversation (docs/SCREEN_READING.md).
 *
 * Everything here is bounded by the project's rules, and they are the reason
 * this is safe to ship at all:
 *  - **Off by default**, and only ever on for the apps on the user's allowlist
 *    ([AppAllowlist]). Screen reading is a bigger ask than notification access
 *    and it is not switched on behind the user's back.
 *  - **Nothing is stored.** The last message text per package lives in a map in
 *    this process's heap and dies with it: no SharedPreferences, no file, no
 *    database, no log (docs/PRIVACY_AND_PERMISSIONS.md).
 *  - **Nothing is sent on the user's behalf.** A screen-read message carries
 *    `hasReplyAction = false`, always - this service types nothing and sends
 *    nothing, in any app, ever.
 *  - **What the user types is never read.** The input box is excluded by
 *    resource id before any text is collected
 *    (`ScreenTextReader`'s excluded-id list, and its test).
 *  - **The Android 16+ caveat is real and documented**: with Advanced
 *    Protection Mode on, the system refuses to grant accessibility access to
 *    an app it does not classify as an accessibility tool, and revokes it from
 *    one already granted. ReplyMate is not an accessibility tool and does not
 *    claim to be one, so on such a device this feature simply will not run.
 */
class ReplyMateScreenReaderService : AccessibilityService() {

    companion object {

        @Volatile
        var instance: ReplyMateScreenReaderService? = null
            private set

        const val KEY_SCREEN_READING_ENABLED = "screen_reading_enabled"

        /**
         * How often the visible conversation may be re-read. A chat repaints
         * for the clock, for a typing dot, for a scroll of one pixel; without a
         * floor the reader would run on every frame of it. 1.2s is well under
         * the time it takes a message to arrive and be read by a human.
         */
        private const val SCAN_INTERVAL_MILLIS = 1_200L

        fun isEnabledByUser(context: Context): Boolean = context
            .getSharedPreferences(
                ReplyMateNotificationListener.PREFS_NAME,
                Context.MODE_PRIVATE,
            )
            .getBoolean(KEY_SCREEN_READING_ENABLED, false)
    }

    /**
     * The last message read per package. Memory only: it exists so an unchanged
     * screen is not re-drafted on every repaint, and it is wiped when the
     * service dies.
     */
    private val lastRead = HashMap<String, String>()

    private var lastScanAtMillis = 0L

    override fun onServiceConnected() {
        instance = this
        lastRead.clear()
    }

    override fun onInterrupt() {
        // Required by the platform; this service holds no feedback to interrupt.
    }

    override fun onDestroy() {
        instance = null
        lastRead.clear()
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val source = event ?: return
        if (!isEnabledByUser(this)) return
        when (source.eventType) {
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            -> Unit
            else -> return
        }
        val packageName = source.packageName?.toString() ?: return
        if (!AppAllowlist.contains(this, packageName)) return

        val now = SystemClock.elapsedRealtime()
        if (now - lastScanAtMillis < SCAN_INTERVAL_MILLIS) return
        lastScanAtMillis = now
        scan(packageName)
    }

    /**
     * Reads the visible conversation once and, when it holds a message the user
     * has not answered yet, hands it to the same pipeline a notification would
     * have used.
     */
    private fun scan(packageName: String) {
        val root = rootInActiveWindow ?: return
        try {
            // The active window may belong to another app entirely - a toast, a
            // keyboard, a system dialog. Reading that would not be "the app the
            // user allowed", so it is dropped before any text is touched.
            if (root.packageName?.toString() != packageName) return

            val tree = AndroidScreenNode(root)
            val message = ScreenTextReader.readNewestMessage(
                tree,
                resources.displayMetrics.widthPixels,
            ) ?: return
            // The newest message is the user's own, so they have already
            // answered; there is nothing here for us to draft.
            if (message.isOutgoing) return
            if (lastRead[packageName] == message.text) return
            lastRead[packageName] = message.text

            val parsed = mapOf<String, Any?>(
                "packageName" to packageName,
                // Stable per message, so a chat that repaints updates the same
                // pending slot instead of stacking a duplicate behind the bubble.
                "key" to "screen:$packageName:${message.text.hashCode()}",
                "title" to ScreenTextReader.readConversationTitle(tree),
                "text" to message.text,
                "isTruncated" to message.isTruncated,
                "isGrouped" to false,
                "isGroupSummary" to false,
                // Nothing was hidden from us by the platform, and nothing is
                // redacted: the text came off the screen the user is looking at.
                "mayBeRedacted" to false,
                // A screen reading gives us no RemoteInput to reply through, and
                // inventing one would mean typing into someone else's app. The
                // UI offers copy / share instead, which is the honest answer.
                "hasReplyAction" to false,
                "replyActionLabel" to null,
                "postedAtMillis" to System.currentTimeMillis(),
                "fromScreen" to true,
            )

            ReplyMateNotificationListener.eventSink?.invoke(
                mapOf("type" to "screen_captured", "notification" to parsed),
            )
            OverlayRouter.route(this, parsed)
        } finally {
            root.recycle()
        }
    }
}
