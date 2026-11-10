package com.keshabstudios.replymate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The "is this message new?" decision, proven without a phone.
 *
 * A phone is exactly where these cases are hard to reproduce on purpose: you
 * cannot scroll a chat by hand and be sure whether the gate fired because of
 * the message or because of the scroll. Here the clock is an argument, so each
 * case is one line.
 */
class ScreenReadingGateTest {

    private companion object {
        const val T0 = 1_000_000L
        const val SETTLED = T0 + ScreenReadingGate.SCROLL_COOLDOWN_MILLIS + 1
    }

    @Test
    fun aMessageSeenForTheFirstTimeIsNew() {
        val gate = ScreenReadingGate()

        assertTrue(gate.shouldEmit("com.whatsapp", "kalke ashbe?", T0))
    }

    @Test
    fun theSameMessageIsNotNewTwice() {
        val gate = ScreenReadingGate()

        assertTrue(gate.shouldEmit("com.whatsapp", "kalke ashbe?", T0))
        assertFalse(gate.shouldEmit("com.whatsapp", "kalke ashbe?", SETTLED))
    }

    @Test
    fun theSameTextInADifferentAppIsStillNew() {
        val gate = ScreenReadingGate()

        assertTrue(gate.shouldEmit("com.whatsapp", "ok", T0))
        // Two people in two apps can both have said "ok"; one app's memory is
        // not evidence about another.
        assertTrue(gate.shouldEmit("org.telegram.messenger", "ok", T0))
    }

    @Test
    fun scrollingBackThroughAChatIsQuiet() {
        val gate = ScreenReadingGate()

        // The newest message arrives while the chat is at the bottom.
        assertTrue(gate.shouldEmit("com.whatsapp", "newest", T0))

        // The user scrolls up: every row that scrolls past is an old message.
        gate.noteScroll(T0 + 100)
        assertFalse(gate.shouldEmit("com.whatsapp", "three days ago", T0 + 200))
        assertFalse(gate.shouldEmit("com.whatsapp", "two days ago", T0 + 300))

        // The scroll settles on one of them, and it does not fire either -
        // this is the row that used to raise a bubble for a message the user
        // was simply re-reading.
        assertFalse(gate.shouldEmit("com.whatsapp", "yesterday", SETTLED))
    }

    @Test
    fun aNewMessageAfterTheScrollSettlesIsHeard() {
        val gate = ScreenReadingGate()

        gate.noteScroll(T0)
        assertFalse(gate.shouldEmit("com.whatsapp", "old message", T0 + 100))

        // A real arrival, after the finger has left the screen.
        assertTrue(gate.shouldEmit("com.whatsapp", "brand new", SETTLED))
    }

    @Test
    fun blankTextIsNeverNew() {
        val gate = ScreenReadingGate()

        assertFalse(gate.shouldEmit("com.whatsapp", "   ", T0))
        assertFalse(gate.shouldEmit("com.whatsapp", "", T0))
    }

    @Test
    fun memoryIsBounded() {
        val gate = ScreenReadingGate()
        repeat(100) { index ->
            gate.shouldEmit("com.whatsapp", "message $index", T0 + index)
        }

        // The gate remembers that a message was seen, not every message it
        // ever saw - a set that grew forever would be retained message content.
        assertEquals(
            ScreenReadingGate.REMEMBERED_PER_PACKAGE,
            gate.rememberedCount("com.whatsapp"),
        )
        // The oldest ones are the ones dropped, so a very old message can be
        // read again - but only after ninety-two newer ones pushed it out.
        assertFalse(gate.shouldEmit("com.whatsapp", "message 99", T0))
        assertFalse(gate.shouldEmit("com.whatsapp", "message 92", T0))
        assertTrue(gate.shouldEmit("com.whatsapp", "message 91", T0))
    }

    @Test
    fun forgettingLetsAMessageBeReadAgain() {
        val gate = ScreenReadingGate()

        assertTrue(gate.shouldEmit("com.whatsapp", "hello", T0))
        gate.forget("com.whatsapp")

        // Clearing local data must be able to clear this too, or the app would
        // be holding message content the user asked it to delete.
        assertTrue(gate.shouldEmit("com.whatsapp", "hello", T0))
    }
}
