package com.keshabstudios.replymate

import android.app.Notification
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
        )
    }
}
