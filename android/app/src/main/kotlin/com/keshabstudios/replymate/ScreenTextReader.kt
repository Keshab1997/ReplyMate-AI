package com.keshabstudios.replymate

/**
 * Reads the newest visible message out of an accessibility node tree.
 *
 * **This file must stay free of Android imports.** Everything here is a pure
 * function of a [ScreenNode] tree: the platform adapter lives in
 * [AndroidScreenNode], the service that receives the events lives in
 * [ReplyMateScreenReaderService]. That split is deliberate and it is the whole
 * reason this logic can be proven at all - the JVM unit test in
 * `android/app/src/test/kotlin/.../ScreenTextReaderTest.kt` builds fake trees
 * and runs the real code, with no device, no emulator and no Android SDK.
 *
 * It is a **heuristic**, and the docs say so (docs/SCREEN_READING.md). Messaging
 * apps give message bubbles no stable resource id, so the tree is read by
 * shape: the message list is the scrolling container with the most children,
 * the newest message is among its last rows, and an incoming bubble is the one
 * that sits on the left half of the screen. When the shape cannot be trusted,
 * this returns null - a message we cannot attribute is a message we do not
 * invent.
 *
 * One shape rule matters more than the rest, and getting it wrong is what made
 * this feature look switched off: **a message row spans the full width of the
 * list in every app this reader targets; the bubble inside it does not.** Every
 * measurement - the width test that separates a bubble from chrome, and the
 * centre that separates an arrival from something the user sent - therefore
 * runs on the node that holds the text, never on the row that contains it.
 */
data class ScreenRect(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
) {
    val centreX: Int get() = (left + right) / 2
    val isPlausible: Boolean get() = right > left && bottom > top
}

/**
 * A read-only view of one accessibility node.
 *
 * The interface exists so a JVM test can hand [ScreenTextReader] a tree built
 * from plain data classes instead of `AccessibilityNodeInfo`, which cannot be
 * constructed off-device.
 */
interface ScreenNode {
    val text: String?
    val viewId: String?
    val className: String?
    val bounds: ScreenRect?
    val children: List<ScreenNode>
}

/** One message read off the screen, with everything we could not promise. */
/**
 * Why a read ended the way it did.
 *
 * "It read nothing" is four different failures, and from outside the phone they
 * look identical: the list was missing, every row was rejected, the newest
 * message was one the user had already sent, or the screen held no text at all.
 * Settings shows this so the difference is visible without adb.
 */
enum class ReadOutcome {
    /** No scrolling container on the screen. */
    NO_LIST,

    /** A list was found, but none of its rows looked readable. */
    NO_ROWS,

    /** Rows were readable but none of them held a message. */
    NO_MESSAGE,

    /** The newest message is one the user sent: nothing to answer. */
    OUTGOING,

    /** A message was read. */
    READ,
}

/**
 * One line of the visible conversation around the newest message.
 *
 * [isOutgoing] is the whole reason this type exists: it is the only place in
 * this app where a line's *author* is known, and conversation memory needs the
 * author to tell "what they said" from "how the user writes"
 * (docs/CONVERSATION_MEMORY.md §8). The notification path cannot say this -
 * a notification only ever carries arrivals.
 */
data class ScreenHistoryLine(
    val text: String,
    val isOutgoing: Boolean,
)

/** What the reader found, and what it had to work with. */
data class ReadResult(
    val message: ScreenMessage?,
    val outcome: ReadOutcome,
    /** How many scrolling containers were on the screen. */
    val listCount: Int,
    /** How many of the chosen list's children looked readable. */
    val rowCount: Int,
    /**
     * The messages visible above [message], oldest first, capped at
     * [ScreenTextReader.MAX_HISTORY_LINES]. Empty is a normal answer - a chat
     * with one message on screen has no history to hand over.
     */
    val history: List<ScreenHistoryLine> = emptyList(),
)

data class ScreenMessage(
    val text: String,
    /** The chat's own title, when the screen exposed one. */
    val conversationTitle: String?,
    /** True when the text was cut at [ScreenTextReader.MAX_TEXT_LENGTH]. */
    val isTruncated: Boolean,
    /**
     * True when the newest message looks like one the user sent. Kept so the
     * caller can decide, honestly, that there is nothing to reply to.
     */
    val isOutgoing: Boolean,
)

object ScreenTextReader {

    /**
     * Screen-read text is capped here; the app drafts a reply, not an essay,
     * and a caption that long is almost always a forward or a copied block.
     */
    const val MAX_TEXT_LENGTH = 2000

    /**
     * How many of the newest list rows are examined before giving up. Three
     * covers a date header, a "typing…" row and the message itself; six
     * absorbs the reaction and quote rows that sit under the newest bubble.
     */
    const val MAX_CANDIDATE_ROWS = 6

    /**
     * How many visible messages of context to hand back with the newest one.
     *
     * Twelve is roughly a phone screen's worth of bubbles, which is the honest
     * limit of "what the user can see while reading the message they asked
     * about". More would be a scroll this reader never performed.
     */
    const val MAX_HISTORY_LINES = 12

    /**
     * Per-line cap for history. Deliberately shorter than [MAX_TEXT_LENGTH]:
     * one forwarded essay must not take the budget of twelve messages.
     */
    const val MAX_HISTORY_TEXT_LENGTH = 500

    /**
     * A bubble this wide is chrome, not a bubble. Every messaging app we target
     * caps a bubble at roughly four fifths of the screen - the input bar, a
     * menu row, a settings row and the "messages are encrypted" notice are the
     * rows that span it. Without this bound a settings screen reads as one
     * enormous message.
     */
    private const val MAX_BUBBLE_WIDTH_FRACTION = 0.92f

    /**
     * Text that belongs to the app's chrome rather than to a message: the box
     * the user types in, the search field, the emoji tray.
     */
    private val EXCLUDED_ID_FRAGMENTS = listOf(
        "entry",
        "search",
        "emoji",
        "input",
        "compose",
        "edit_text",
        "conversation_contact_name",
        "toolbar",
        "action_bar",
    )

    /** Rows that carry no message: separators, receipts, typing indicators. */
    private val NOISE_PATTERNS = listOf(
        Regex("""^\d{1,2}[:.]\d{2}\s*(am|pm)?$""", RegexOption.IGNORE_CASE),
        Regex("""^typing(\.*|…)$""", RegexOption.IGNORE_CASE),
        Regex("""^(today|yesterday|taday|tomorrow)$""", RegexOption.IGNORE_CASE),
        Regex("""^(online|last seen.*|offline)$""", RegexOption.IGNORE_CASE),
        Regex("""^messages (you send|and calls) .*$""", RegexOption.IGNORE_CASE),
        Regex("""^\p{Punct}+$"""),
    )

    /** Ids that carry the conversation's name, in the apps we have seen. */
    private val TITLE_ID_FRAGMENTS = listOf(
        "conversation_contact_name",
        "contact_name",
        "conversation_title",
        "action_bar_title",
        "title",
    )

    /**
     * The newest visible message, or null when the screen holds nothing this
     * reader is willing to call a message.
     *
     * @param root the active window's root node.
     * @param screenWidth the display width in pixels, used only to tell the
     *   left half of the screen from the right one.
     */
    fun readNewestMessage(root: ScreenNode, screenWidth: Int): ScreenMessage? =
        read(root, screenWidth).message

    /**
     * The same read, with what it had to work with.
     *
     * The plain answer is [readNewestMessage]; this is the one the service
     * uses, because a feature that silently reads nothing cannot be fixed from
     * the outside without knowing which of the five ways it failed.
     */
    fun read(root: ScreenNode, screenWidth: Int): ReadResult {
        if (screenWidth <= 0) return ReadResult(null, ReadOutcome.NO_LIST, 0, 0)

        // The scrolling container with the most children: in every messaging app
        // this reader targets, the conversation is the biggest list on screen. A
        // layout with two equally large lists is not one we claim to understand,
        // so the tie is resolved by taking the lower one (the chat sits below
        // the header in every app we have seen).
        //
        // A container with a single child still counts - a two-message chat is a
        // conversation, and refusing to read it because the list is short is the
        // kind of false negative that looks like a broken feature.
        val lists = mutableListOf<ScreenNode>()
        collectLists(root, lists)
        val list = lists.maxWithOrNull(
            compareBy<ScreenNode> { it.children.size }.thenBy { it.bounds?.top ?: 0 },
        ) ?: return ReadResult(null, ReadOutcome.NO_LIST, lists.size, 0)

        val rows = list.children.filter { it.isVisibleRow() }
        if (rows.isEmpty()) return ReadResult(null, ReadOutcome.NO_ROWS, lists.size, 0)

        // The search window for the *newest message* stays at
        // MAX_CANDIDATE_ROWS: it is the shape proven on devices, and widening it
        // would read a chrome row as the message. The history walk below starts
        // from wherever this search stopped, so the two limits do not have to be
        // the same number.
        val windowStart = (rows.size - MAX_CANDIDATE_ROWS).coerceAtLeast(0)
        var newestIndex = -1
        var candidate: ScreenMessage? = null
        var index = rows.lastIndex
        while (index >= windowStart) {
            val read = readRow(rows[index], screenWidth)
            if (read != null) {
                candidate = read
                newestIndex = index
                break
            }
            index--
        }
        if (candidate == null) {
            return ReadResult(null, ReadOutcome.NO_MESSAGE, lists.size, rows.size)
        }
        return ReadResult(
            candidate,
            if (candidate.isOutgoing) ReadOutcome.OUTGOING else ReadOutcome.READ,
            lists.size,
            rows.size,
            // Everything above the message being answered, handed back oldest
            // first. Never a row below it: those were rejected above, and
            // pulling them in would mean answering a message that is no longer
            // the newest one.
            history = readHistory(rows, newestIndex, screenWidth),
        )
    }

    private fun collectLists(node: ScreenNode, into: MutableList<ScreenNode>) {
        if (node.isScrollingContainer() && node.children.isNotEmpty()) into.add(node)
        node.children.forEach { collectLists(it, into) }
    }

    private fun ScreenNode.isScrollingContainer(): Boolean {
        val name = className.orEmpty()
        return name.contains("RecyclerView", ignoreCase = true) ||
            name.contains("ListView", ignoreCase = true) ||
            name.contains("ScrollView", ignoreCase = true)
    }

    /**
     * A row worth reading: it has a plausible rectangle and holds at least one
     * text node that is not the app's own chrome.
     *
     * Deliberately **not** filtered by width. A message row is as wide as the
     * list in every app this reader targets, so a width test on the row throws
     * away the entire conversation; the bubble inside it is measured in
     * [readRow], which is the only place a width says anything.
     */
    private fun ScreenNode.isVisibleRow(): Boolean {
        val rect = bounds ?: return false
        if (!rect.isPlausible) return false
        return collectTextNodes().any { it.isReadableText() }
    }

    /**
     * Reads one row as a message, or returns null when the row is not one.
     *
     * The id filter runs on the *nodes*, before the text is collected: a draft
     * sitting in the input box is text on the same screen as the message, and
     * sending what the user is typing to an AI is the one mistake this feature
     * must never make.
     */
    private fun readRow(row: ScreenNode, screenWidth: Int): ScreenMessage? {
        val texts = row.collectTextNodes()
            .filter { it.isReadableText() }
            .mapNotNull { node ->
                val value = node.text?.trim().orEmpty()
                // The node is kept next to its text: the rectangle that says
                // whether this arrived or was sent belongs to that node, not to
                // the row, and throwing it away here is what broke reading.
                if (value.isBlank()) null else (node to value)
            }
            .filterNot { (_, text) -> NOISE_PATTERNS.any { it.matches(text) } }
        if (texts.isEmpty()) return null

        // A bubble holds the message plus its furniture - the time, and in a
        // group the sender's name. The longest readable string is the message,
        // and the node holding it is the bubble that can be measured.
        val (node, message) = texts.maxByOrNull { (_, text) -> text.length }
            ?: return null

        // Measure the bubble, not the row. A row spans the full width of the
        // list; measuring it rejected every message on the screen, which from
        // the outside is indistinguishable from the feature being off. The row
        // is only a fallback for an app that reports no bounds on its text.
        val rect = node.bounds ?: row.bounds ?: return null
        val width = rect.right - rect.left
        if (width > screenWidth * MAX_BUBBLE_WIDTH_FRACTION) return null
        val isOutgoing = rect.centreX > screenWidth / 2
        val truncated = message.length > MAX_TEXT_LENGTH

        return ScreenMessage(
            text = if (truncated) message.take(MAX_TEXT_LENGTH) else message,
            conversationTitle = null,
            isTruncated = truncated,
            isOutgoing = isOutgoing,
        )
    }

    /**
     * The messages above the newest one, oldest first.
     *
     * Same row reader as the newest message, so a line of chrome is rejected by
     * exactly the same rules in both places - the history must never be more
     * trusting than the message it belongs to. A row this reader cannot read is
     * skipped rather than stopping the walk: one unreadable reaction row must
     * not throw away the conversation above it.
     */
    private fun readHistory(
        rows: List<ScreenNode>,
        newestIndex: Int,
        screenWidth: Int,
    ): List<ScreenHistoryLine> {
        val collected = mutableListOf<ScreenHistoryLine>()
        // Bounded work as well as a bounded result: a row this reader cannot
        // read is skipped rather than ending the walk, so one reaction row does
        // not throw away the conversation above it - but the walk still stops,
        // because a fixed budget is what keeps this cheap on every event.
        val budget = MAX_HISTORY_LINES + MAX_CANDIDATE_ROWS
        var examined = 0
        var index = newestIndex - 1
        while (index >= 0 && collected.size < MAX_HISTORY_LINES && examined < budget) {
            examined++
            val line = readRow(rows[index], screenWidth)
            if (line != null) {
                val text = line.text.trim()
                if (text.isNotEmpty()) {
                    collected.add(
                        ScreenHistoryLine(
                            text = text.take(MAX_HISTORY_TEXT_LENGTH),
                            isOutgoing = line.isOutgoing,
                        ),
                    )
                }
            }
            index--
        }
        // Walked newest first, handed back oldest first - the order every
        // prompt and every memory window expects.
        return collected.asReversed()
    }

    /**
     * The conversation title, when the screen exposes one. Null is a normal
     * answer, not a failure: the UI then falls back to the app's name.
     */
    fun readConversationTitle(root: ScreenNode): String? {
        val byId = mutableListOf<String>()
        collectTitleById(root, byId)
        return byId.firstOrNull { it.isNotBlank() && it.isReadableText() }?.trim()
    }

    private fun collectTitleById(node: ScreenNode, into: MutableList<String>) {
        val id = node.viewId.orEmpty()
        if (TITLE_ID_FRAGMENTS.any { id.contains(it, ignoreCase = true) }) {
            node.text?.let { into.add(it) }
            node.children.forEach { child -> child.text?.let { into.add(it) } }
        }
        node.children.forEach { collectTitleById(it, into) }
    }

    /** Every node in this subtree that carries text, in reading order. */
    private fun ScreenNode.collectTextNodes(): List<ScreenNode> {
        val out = mutableListOf<ScreenNode>()
        fun walk(node: ScreenNode) {
            if (!node.text.isNullOrBlank()) out.add(node)
            node.children.forEach { walk(it) }
        }
        walk(this)
        return out
    }

    /**
     * Text this reader is allowed to hand to the AI: not the app's input box,
     * and not a one-character tick.
     */
    private fun String.isReadableText(): Boolean {
        if (length < 2) return false
        return true
    }

    private fun ScreenNode.isReadableText(): Boolean {
        val value = text?.trim() ?: return false
        if (value.length < 2) return false
        val id = viewId.orEmpty()
        if (EXCLUDED_ID_FRAGMENTS.any { id.contains(it, ignoreCase = true) }) return false
        return true
    }
}
