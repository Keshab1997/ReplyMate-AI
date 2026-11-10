package com.keshabstudios.replymate

import android.app.Notification
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.StatusBarNotification

/**
 * Extracts only the fields Android actually makes available from a posted
 * notification, and reports honestly when content is missing, truncated,
 * grouped or redacted (FR-04).
 *
 * The produced map is the wire format of the `notification_captured` event;
 * the contract is documented in docs/PLATFORM_CHANNELS.md and mirrored by
 * `CapturedNotification.fromMap` on the Dart side.
 *
 * Pure function of the notification: no I/O, no state, so it can be reasoned
 * about (and tested) without a device.
 */
object NotificationParser {

    /** Android caps EXTRA_BIG_TEXT at this many characters; hitting it means cut text. */
    private const val BIG_TEXT_TRUNCATION_LIMIT = 5120

    /** Android's own key for the text of one MessagingStyle message. */
    private const val KEY_MESSAGE_TEXT = "text"

    fun parse(sbn: StatusBarNotification): Map<String, Any?> {
        val notification = sbn.notification
        val extras = notification.extras

        val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        var text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        val bigText = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()

        // Some apps carry the message body only in BIG_TEXT.
        if (text.isNullOrEmpty() && !bigText.isNullOrEmpty()) {
            text = bigText
        }
        // BIG_TEXT longer than TEXT means TEXT held only a summary line, and a
        // BIG_TEXT at the platform cap was cut mid-sentence.
        val truncatedByLimit = (bigText?.length ?: 0) >= BIG_TEXT_TRUNCATION_LIMIT
        val truncatedByEllipsis =
            text?.let { it.endsWith("…") || it.endsWith("...") } == true

        // A reply action is only a reply action when it actually carries a
        // RemoteInput; every other action (open, call, archive) is not one.
        val replyAction = notification.actions?.firstOrNull { action ->
            !(action?.remoteInputs.isNullOrEmpty())
        }

        return mapOf(
            "packageName" to sbn.packageName,
            "key" to sbn.key,
            "title" to title,
            "text" to text,
            "isTruncated" to (truncatedByLimit || truncatedByEllipsis),
            "isGrouped" to (notification.group != null),
            "isGroupSummary" to
                ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0),
            // Anything that is not VISIBILITY_PUBLIC may arrive redacted on
            // the lock screen; the app must say so instead of guessing.
            "mayBeRedacted" to (notification.visibility != Notification.VISIBILITY_PUBLIC),
            "hasReplyAction" to (replyAction != null),
            "replyActionLabel" to replyAction?.title?.toString(),
            "postedAtMillis" to sbn.postTime,
            "priorMessages" to priorMessages(extras, text),
        )
    }

    /**
     * The lines that came before the newest one, oldest first.
     *
     * A messaging app posts a conversation, not a line: Android carries the
     * recent exchange inside the notification itself, and reading it is the
     * only way to answer "shall we move it to Friday?" knowing what "it" is -
     * without reading the screen and without one extra permission.
     *
     * Coming back empty is a normal answer. Plenty of apps post only the line
     * that triggered the notification, and the app simply replies to what it
     * has, which is exactly what it did before.
     */
    private fun priorMessages(extras: Bundle?, newest: String?): List<String> {
        val raw = mutableListOf<String>()
        readMessageBundles(
            extras?.getParcelableArray(Notification.EXTRA_HISTORIC_MESSAGES),
            raw,
        )
        readMessageBundles(
            extras?.getParcelableArray(Notification.EXTRA_MESSAGES),
            raw,
        )
        if (raw.isEmpty()) {
            extras
                ?.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
                ?.forEach { line -> raw.add(line?.toString().orEmpty()) }
        }
        return ConversationHistory.fromLines(raw, newest)
    }

    @Suppress("DEPRECATION")
    private fun readMessageBundles(
        array: Array<Parcelable>?,
        into: MutableList<String>,
    ) {
        array ?: return
        for (item in array) {
            val bundle = item as? Bundle ?: continue
            val value = bundle.getCharSequence(KEY_MESSAGE_TEXT)?.toString()
            if (!value.isNullOrEmpty()) into.add(value)
        }
    }
}
