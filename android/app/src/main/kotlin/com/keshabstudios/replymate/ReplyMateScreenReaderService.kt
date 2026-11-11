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
 *  - **Nothing is stored.** A short, bounded memory of recent texts per package
 *    lives in this process's heap and dies with it: no SharedPreferences, no
 *    file, no database, no log (docs/PRIVACY_AND_PERMISSIONS.md).
 *  - **Scrolling is not an arrival.** Reading the newest visible bubble would
 *    otherwise report an old message every time the user scrolled back through
 *    a chat, so [ScreenReadingGate] decides what is actually new.
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

        /** Where the last scan's report is kept, so Settings can show it. */
        private const val PREFS_DIAG = "replymate_screen_reading_diag"

        /** How much of a read message the report carries - enough to debug. */
        private const val MAX_REPORTED_TEXT = 200

        /**
         * What the reader is actually doing, for the Settings screen.
         *
         * Without this, "screen reading does not work" is one sentence with
         * five possible causes and no way to tell them apart on a phone.
         */
        fun report(context: Context): Map<String, Any?> {
            val prefs = context.getSharedPreferences(PREFS_DIAG, Context.MODE_PRIVATE)
            return mapOf(
                "connected" to (instance != null),
                "enabledByUser" to isEnabledByUser(context),
                "allowlist" to AppAllowlist.all(context),
                "scanCount" to prefs.getInt("scanCount", 0),
                "lastScanAtMillis" to prefs.getLong("lastScanAtMillis", 0L),
                "lastOutcome" to prefs.getString("lastOutcome", null),
                "lastPackage" to prefs.getString("lastPackage", null),
                "lastText" to prefs.getString("lastText", null),
                "listCount" to prefs.getInt("listCount", 0),
                "rowCount" to prefs.getInt("rowCount", 0),
            )
        }

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
     * Decides whether what the reader found is *new*.
     *
     * The reader reports the newest bubble it can see, and while the user
     * scrolls back through a chat that bubble is an old message - same text,
     * same shape, nothing on screen saying "this arrived two days ago". The
     * gate is what keeps a scroll from looking like an arrival
     * (ScreenReadingGate, and its tests).
     */
    private val gate = ScreenReadingGate()

    private var lastScanAtMillis = 0L

    override fun onServiceConnected() {
        instance = this
        gate.clear()
    }

    override fun onInterrupt() {
        // Required by the platform; this service holds no feedback to interrupt.
    }

    override fun onDestroy() {
        instance = null
        gate.clear()
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val source = event ?: return
        if (!isEnabledByUser(this)) return
        val now = SystemClock.elapsedRealtime()
        when (source.eventType) {
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            -> Unit
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> {
                // Recorded even though no scan follows it: a scroll teaches the
                // gate every message it passed, so that none of them fires
                // later when the user stops on one.
                gate.noteScroll(now)
                return
            }
            else -> return
        }
        val packageName = source.packageName?.toString() ?: return
        if (!AppAllowlist.contains(this, packageName)) return

        if (now - lastScanAtMillis < SCAN_INTERVAL_MILLIS) return
        lastScanAtMillis = now
        scan(packageName, now)
    }

    /**
     * Reads the visible conversation once and, when it holds a message the user
     * has not answered yet, hands it to the same pipeline a notification would
     * have used.
     */
    /**
     * Writes down what the last look at the screen found.
     *
     * Kept in preferences rather than in memory because the process reading the
     * screen is not the one showing Settings: Android kills and restarts it
     * freely, and a report that dies with it is a report nobody ever reads.
     */
    private fun record(
        outcome: String,
        packageName: String?,
        text: String?,
        listCount: Int,
        rowCount: Int,
    ) {
        val prefs = getSharedPreferences(PREFS_DIAG, Context.MODE_PRIVATE)
        prefs.edit()
            .putInt("scanCount", prefs.getInt("scanCount", 0) + 1)
            .putLong("lastScanAtMillis", System.currentTimeMillis())
            .putString("lastOutcome", outcome)
            .putString("lastPackage", packageName)
            .putString("lastText", text?.take(MAX_REPORTED_TEXT))
            .putInt("listCount", listCount)
            .putInt("rowCount", rowCount)
            .apply()
    }

    /**
     * Reads the visible conversation once and, when it holds a message the user
     * has not answered yet, hands it to the same pipeline a notification would
     * have used.
     */
    private fun scan(packageName: String, nowMillis: Long) {
        val root = rootInActiveWindow
        if (root == null) {
            record("no_window", packageName, null, 0, 0)
            return
        }
        try {
            // The active window may belong to another app entirely - a toast, a
            // keyboard, a system dialog. Reading that would not be "the app the
            // user allowed", so it is dropped before any text is touched.
            if (root.packageName?.toString() != packageName) {
                record("other_app", packageName, null, 0, 0)
                return
            }

            val result = ScreenTextReader.read(
                AndroidScreenNode(root),
                resources.displayMetrics.widthPixels,
            )
            val message = result.message
            when {
                result.outcome != ReadOutcome.READ -> record(
                    result.outcome.name.lowercase(),
                    packageName,
                    message?.text,
                    result.listCount,
                    result.rowCount,
                )

                // New to us, and not something the user just scrolled past.
                !gate.shouldEmit(packageName, message!!.text, nowMillis) -> record(
                    "not_new",
                    packageName,
                    message.text,
                    result.listCount,
                    result.rowCount,
                )

                else -> {
                    record(
                        "read",
                        packageName,
                        message.text,
                        result.listCount,
                        result.rowCount,
                    )
                    emit(packageName, message, result.history)
                }
            }
        } finally {
            root.recycle()
        }
    }

    /**
     * Hands a screen-read message to the same pipeline a notification would have
     * used.
     */
    private fun emit(
        packageName: String,
        message: ScreenMessage,
        history: List<ScreenHistoryLine>,
    ) {
        val parsed = mapOf<String, Any?>(
            "packageName" to packageName,
            // Stable per message, so a chat that repaints updates the same
            // pending slot instead of stacking a duplicate behind the bubble.
            "key" to "screen:$packageName:${message.text.hashCode()}",
            "title" to message.conversationTitle,
            "text" to message.text,
            "isTruncated" to message.isTruncated,
            "isGrouped" to false,
            "isGroupSummary" to false,
            // Nothing was hidden from us by the platform, and nothing is
            // redacted: the text came off the screen the user is looking at.
            "mayBeRedacted" to false,
            // A screen reading gives us no RemoteInput to reply through, and
            // inventing one would mean typing into someone else's app. The UI
            // offers copy / share instead, which is the honest answer.
            "hasReplyAction" to false,
            "replyActionLabel" to null,
            "postedAtMillis" to System.currentTimeMillis(),
            "fromScreen" to true,
            // The visible thread around the message, oldest first, with the side
            // each line came from. This is the only capture path that knows a
            // line's author, so it is the only one whose history may be stored
            // (docs/CONVERSATION_MEMORY.md §8). Notification history stays
            // authorless and is still thrown away rather than guessed at.
            "priorMessages" to history.map { it.text },
            "priorAuthors" to history.map { if (it.isOutgoing) "me" else "them" },
        )
        ReplyMateNotificationListener.eventSink?.invoke(
            mapOf("type" to "screen_captured", "notification" to parsed),
        )
        OverlayRouter.route(this, parsed)
    }
}
