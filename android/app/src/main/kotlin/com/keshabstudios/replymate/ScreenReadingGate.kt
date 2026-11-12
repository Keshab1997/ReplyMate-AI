package com.keshabstudios.replymate

/**
 * Decides whether a message read off the screen is *new* - the question the
 * reader itself cannot answer.
 *
 * `ScreenTextReader` reports the newest bubble it can see. While the user
 * scrolls back through a chat, that bubble is an old message: same text, same
 * shape, and nothing on screen says "this arrived two days ago". Emitting it
 * would raise a bubble for a message the user is re-reading, and with
 * auto-drafting it would spend an API call on it too.
 *
 * The rule this class applies:
 *  - a text seen before, for that package, is not new;
 *  - anything seen *while scrolling* is remembered but never emitted, so the
 *    message the user lands on when the scroll stops does not fire either;
 *  - once the scroll has settled, a genuinely new message is emitted again.
 *
 * Like `ScreenTextReader` this file is free of Android imports and takes the
 * clock as an argument, so every branch of it is proven on a plain JVM
 * (`ScreenReadingGateTest.kt`).
 *
 * Nothing here is persisted: the remembered texts live in this object's heap,
 * which dies with the service.md §3 rule 5).
 */
class ScreenReadingGate {

    companion object {
        /**
         * How long a scroll keeps the gate closed after the last scroll event.
         * Long enough to cover a flick that is still settling, short enough
         * that a message arriving right after a scroll is not swallowed.
         */
        const val SCROLL_COOLDOWN_MILLIS = 1_500L

        /**
         * How many recent texts are remembered per package. This is a memory
         * bound, not a feature: three chats' worth of scrolling is plenty, and
         * a set that grew forever would be the one thing this feature is not
         * allowed to do - retain message content.
         */
        const val REMEMBERED_PER_PACKAGE = 8
    }

    /** Newest last, per package. Bounded by [REMEMBERED_PER_PACKAGE]. */
    private val remembered = LinkedHashMap<String, MutableList<String>>()

    /**
     * Null until the first scroll, deliberately: a sentinel timestamp would
     * have to be subtracted from `now`, and the obvious one
     * (`Long.MIN_VALUE`) overflows into "definitely scrolling" - a gate that
     * never opens until someone scrolls, which is exactly backwards.
     */
    private var lastScrollAtMillis: Long? = null

    /** Called for every scroll event, whether or not a scan follows it. */
    fun noteScroll(nowMillis: Long) {
        lastScrollAtMillis = nowMillis
    }

    /** True while a scroll is still settling. */
    fun isScrolling(nowMillis: Long): Boolean {
        val last = lastScrollAtMillis ?: return false
        return nowMillis - last < SCROLL_COOLDOWN_MILLIS
    }

    /**
     * Whether [text] is new for [packageName] and worth handing on.
     *
     * A text is remembered whether or not it is emitted: scrolling past an old
     * message teaches the gate that message, so it stays quiet when the user
     * stops on it. The cost of that choice is honest and deliberate - a
     * message the user scrolled back to does not raise a bubble even if they
     * never answered it.
     */
    fun shouldEmit(packageName: String, text: String, nowMillis: Long): Boolean {
        if (text.isBlank()) return false
        val seen = remembered.getOrPut(packageName) { mutableListOf() }
        if (seen.contains(text)) return false
        seen.add(text)
        while (seen.size > REMEMBERED_PER_PACKAGE) seen.removeAt(0)
        return !isScrolling(nowMillis)
    }

    /**
     * How many texts are remembered for [packageName].
     *
     * Exposed so the memory bound is asserted rather than assumed: this gate
     * is the one object in the feature that holds message text over time, and
     * "it stays bounded" is a promise worth a test
     * md §3 rule 5).
     */
    fun rememberedCount(packageName: String): Int =
        remembered[packageName]?.size ?: 0

    /**
     * Drops everything remembered for one package - used when the user clears
     * local data, so a forgotten message can be read again rather than being
     * suppressed by a memory they asked us to delete.
     */
    fun forget(packageName: String) {
        remembered.remove(packageName)
    }

    /** Drops everything. Called when the service goes away. */
    fun clear() {
        remembered.clear()
        lastScrollAtMillis = null
    }
}
