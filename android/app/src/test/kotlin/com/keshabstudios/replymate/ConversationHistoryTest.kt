package com.keshabstudios.replymate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The JVM proof for [ConversationHistory]: fake lines in, asserted lines out,
 * no device, no emulator and no Android SDK.
 *
 * The cases that matter here are the ones that would otherwise be invisible on
 * a phone: a thread long enough to be cut, a line long enough to be capped, and
 * the newest message turning up in its own history.
 */
class ConversationHistoryTest {

    @Test
    fun `the newest line is not repeated as its own history`() {
        val history = ConversationHistory.fromLines(
            listOf("Are we still on for tomorrow?", "Yes - 4pm?"),
            "Yes - 4pm?",
        )

        assertEquals(listOf("Are we still on for tomorrow?"), history)
    }

    @Test
    fun `the newest line is matched after trimming`() {
        val history = ConversationHistory.fromLines(
            listOf("Are we on?", "  Yes - 4pm?  "),
            "Yes - 4pm?",
        )

        assertEquals(listOf("Are we on?"), history)
    }

    @Test
    fun `blank lines never reach the prompt`() {
        val history = ConversationHistory.fromLines(
            listOf("", "   ", "Are we on?", ""),
            "Yes",
        )

        assertEquals(listOf("Are we on?"), history)
    }

    @Test
    fun `a repeated line is carried once`() {
        val history = ConversationHistory.fromLines(
            listOf("Ping", "Ping", "Ping"),
            "Pong",
        )

        assertEquals(listOf("Ping"), history)
    }

    @Test
    fun `a long thread keeps the newest lines, not the oldest`() {
        val raw = (1..20).map { "line $it" }

        val history = ConversationHistory.fromLines(raw, "line 21")

        assertEquals(ConversationHistory.MAX_PRIOR_MESSAGES, history.size)
        assertEquals("line 20", history.last())
        assertEquals("line 15", history.first())
    }

    @Test
    fun `an oversized line is cut rather than dropped`() {
        val long = "x".repeat(ConversationHistory.MAX_PRIOR_MESSAGE_LENGTH + 500)

        val history = ConversationHistory.fromLines(listOf(long), "newest")

        assertEquals(1, history.size)
        assertEquals(
            ConversationHistory.MAX_PRIOR_MESSAGE_LENGTH,
            history.single().length,
        )
    }

    @Test
    fun `no history is an empty list, not a failure`() {
        assertTrue(ConversationHistory.fromLines(emptyList(), "only message").isEmpty())
        assertTrue(ConversationHistory.fromLines(emptyList(), null).isEmpty())
    }

    @Test
    fun `history of nothing but the message itself is empty`() {
        assertTrue(ConversationHistory.fromLines(listOf("Hi"), "Hi").isEmpty())
    }
}
