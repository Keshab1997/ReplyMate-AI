package com.keshabstudios.replymate

/**
 * The messages that came before the newest one.
 *
 * A notification is not only the line that triggered it. Messaging apps post
 * conversations, and Android carries the recent exchange inside the
 * notification itself: `EXTRA_MESSAGES` / `EXTRA_HISTORIC_MESSAGES` for
 * MessagingStyle, `EXTRA_TEXT_LINES` for the apps that do not use it. Reading
 * those is how the app can answer "shall we move it to Friday?" having seen
 * what "it" is - without reading anything off the screen and without asking
 * for one extra permission.
 *
 * This is text the platform had already handed to the notification shade.
 * Nothing new is read, nothing is fetched, and nothing is stored: the lines
 * travel with the capture and die with it.
 *
 * **This file must stay free of Android imports.** It is a pure function of the
 * lines it is handed, which is the only reason it can be proven on the JVM -
 * see `ConversationHistoryTest`. The Bundle-shaped work of getting those lines
 * out of a notification lives in [NotificationParser].
 */
object ConversationHistory {

    /**
     * How many earlier lines are worth carrying. Six is a whole short exchange
     * and still small enough that the newest line keeps its weight in the
     * prompt; a longer thread is cut at the front, not the back.
     */
    const val MAX_PRIOR_MESSAGES = 6

    /** One earlier line is capped here: context, not a second conversation. */
    const val MAX_PRIOR_MESSAGE_LENGTH = 400

    /**
     * @param raw every line the notification exposed, oldest first. Duplicated,
     *   blank and oversized entries are normal and are handled here.
     * @param newest the line already carried as the message itself. It is
     *   dropped from the history so the model is not asked to answer it twice.
     */
    fun fromLines(raw: List<String>, newest: String?): List<String> {
        val key = newest?.trim().orEmpty()
        val seen = LinkedHashSet<String>()
        for (line in raw) {
            val value = line.trim()
            if (value.isEmpty()) continue
            // The message itself is the newest line in most apps; keeping it in
            // the history too would put the question and the answer together.
            if (key.isNotEmpty() && value == key) continue
            seen.add(
                if (value.length > MAX_PRIOR_MESSAGE_LENGTH) {
                    value.take(MAX_PRIOR_MESSAGE_LENGTH)
                } else {
                    value
                },
            )
        }
        return seen.toList().takeLast(MAX_PRIOR_MESSAGES)
    }
}
