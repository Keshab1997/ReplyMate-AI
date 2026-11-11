package com.keshabstudios.replymate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The one part of screen reading that can be proven without a phone.
 *
 * `ScreenTextReader` takes a [ScreenNode] tree, so these tests build the same
 * tree WhatsApp hands an accessibility service - a RecyclerView of bubbles,
 * each with a message, a time and a rectangle - and assert what the reader
 * concludes from it. No Android classes are constructed here, which is why
 * this runs on a plain JVM.
 */
class ScreenTextReaderTest {

    /** A node built from data, standing in for `AccessibilityNodeInfo`. */
    private class FakeNode(
        override val text: String? = null,
        override val viewId: String? = null,
        override val className: String? = null,
        override val bounds: ScreenRect? = null,
        override val children: List<ScreenNode> = emptyList(),
    ) : ScreenNode

    private companion object {
        const val SCREEN_WIDTH = 1080

        /** An incoming bubble: left-aligned, 70% of the screen wide. */
        fun incomingBubble(message: String, top: Int = 400): ScreenNode =
            FakeNode(
                className = "android.widget.FrameLayout",
                bounds = ScreenRect(40, top, 760, top + 120),
                children = listOf(
                    FakeNode(text = message, className = "android.widget.TextView"),
                    FakeNode(text = "10:42", className = "android.widget.TextView"),
                ),
            )

        /** An outgoing bubble: right-aligned, same size. */
        fun outgoingBubble(message: String, top: Int = 400): ScreenNode =
            FakeNode(
                className = "android.widget.FrameLayout",
                bounds = ScreenRect(320, top, 1040, top + 120),
                children = listOf(
                    FakeNode(text = message, className = "android.widget.TextView"),
                    FakeNode(text = "10:43", className = "android.widget.TextView"),
                ),
            )

        /**
         * The shape WhatsApp actually hands a service: a row the width of the
         * screen, holding a bubble that is not.
         *
         * The older fake rows were 720px wide on a 1080px screen, which is not
         * how a RecyclerView item is laid out - and that is exactly why a width
         * test on the row passed every test and read nothing on a phone.
         */
        fun fullWidthRow(message: String, top: Int, incoming: Boolean): ScreenNode {
            val left = if (incoming) 30 else 420
            val right = if (incoming) 780 else 1050
            return FakeNode(
                className = "android.widget.FrameLayout",
                bounds = ScreenRect(0, top, SCREEN_WIDTH, top + 120),
                children = listOf(
                    FakeNode(
                        className = "android.widget.LinearLayout",
                        bounds = ScreenRect(left, top, right, top + 120),
                        children = listOf(
                            FakeNode(
                                text = message,
                                className = "android.widget.TextView",
                                bounds = ScreenRect(left + 20, top + 10, right - 20, top + 70),
                            ),
                            FakeNode(
                                text = "10:42",
                                className = "android.widget.TextView",
                                bounds = ScreenRect(right - 90, top + 80, right - 20, top + 110),
                            ),
                        ),
                    ),
                ),
            )
        }

        fun chatScreen(vararg rows: ScreenNode, title: String? = "Riya"): ScreenNode =
            FakeNode(
                className = "android.widget.FrameLayout",
                children = listOf(
                    FakeNode(
                        viewId = "com.whatsapp:id/action_bar_root",
                        className = "android.widget.LinearLayout",
                        children = listOf(
                            FakeNode(
                                viewId = "com.whatsapp:id/conversation_contact_name",
                                text = title,
                                className = "android.widget.TextView",
                            ),
                        ),
                    ),
                    FakeNode(
                        className = "androidx.recyclerview.widget.RecyclerView",
                        children = rows.toList(),
                    ),
                ),
            )
    }

    @Test
    fun readsTheNewestIncomingMessage() {
        val screen = chatScreen(
            incomingBubble("kalke meeting e ashbe?", top = 200),
            incomingBubble("haan, ashchi", top = 340),
        )

        val message = ScreenTextReader.readNewestMessage(screen, SCREEN_WIDTH)

        assertEquals("haan, ashchi", message?.text)
        assertFalse(message!!.isOutgoing)
        assertFalse(message.isTruncated)
    }

    @Test
    fun readsTheConversationTitle() {
        val screen = chatScreen(incomingBubble("hello"))

        assertEquals("Riya", ScreenTextReader.readConversationTitle(screen))
    }

    @Test
    fun skipsDateHeadersAndTypingIndicators() {
        val screen = chatScreen(
            incomingBubble("first message", top = 200),
            FakeNode(
                className = "android.widget.TextView",
                text = "TODAY",
                bounds = ScreenRect(400, 340, 680, 380),
            ),
            FakeNode(
                className = "android.widget.TextView",
                text = "typing…",
                bounds = ScreenRect(40, 400, 760, 440),
            ),
        )

        val message = ScreenTextReader.readNewestMessage(screen, SCREEN_WIDTH)

        assertEquals("first message", message?.text)
    }

    @Test
    fun reportsTheUsersOwnMessageAsOutgoing() {
        val screen = chatScreen(
            incomingBubble("ashbe?", top = 200),
            outgoingBubble("ashchi", top = 340),
        )

        val message = ScreenTextReader.readNewestMessage(screen, SCREEN_WIDTH)

        // The reader reports what it saw and flags whose it is; the service is
        // what decides that a message the user just sent is not a message the
        // user wants to answer. Both facts belong on the record.
        assertEquals("ashchi", message?.text)
        assertTrue(message!!.isOutgoing)
    }

    @Test
    fun neverCapturesWhatTheUserIsTyping() {
        val screen = chatScreen(
            FakeNode(
                className = "android.widget.FrameLayout",
                bounds = ScreenRect(40, 340, 760, 460),
                children = listOf(
                    FakeNode(text = "party te ashbe?", className = "android.widget.TextView"),
                    FakeNode(
                        text = "ami ashbo na bole dibo",
                        viewId = "com.whatsapp:id/entry",
                        className = "android.widget.EditText",
                    ),
                ),
            ),
        )

        val message = ScreenTextReader.readNewestMessage(screen, SCREEN_WIDTH)

        assertEquals("party te ashbe?", message?.text)
    }

    @Test
    fun marksVeryLongTextAsTruncated() {
        val long = "a".repeat(ScreenTextReader.MAX_TEXT_LENGTH + 500)
        val screen = chatScreen(incomingBubble(long))

        val message = ScreenTextReader.readNewestMessage(screen, SCREEN_WIDTH)

        assertTrue(message!!.isTruncated)
        assertEquals(ScreenTextReader.MAX_TEXT_LENGTH, message.text.length)
    }

    @Test
    fun returnsNullWhenThereIsNoConversationOnScreen() {
        val home = FakeNode(
            className = "android.widget.FrameLayout",
            children = listOf(
                FakeNode(
                    className = "androidx.recyclerview.widget.RecyclerView",
                    children = listOf(
                        FakeNode(
                            text = "Settings",
                            className = "android.widget.TextView",
                            bounds = ScreenRect(0, 100, SCREEN_WIDTH, 180),
                        ),
                    ),
                ),
            ),
        )

        // One row is not a conversation, and a menu row is not a message we
        // would hand to an AI.
        assertNull(ScreenTextReader.readNewestMessage(home, SCREEN_WIDTH))
    }

    @Test
    fun refusesToGuessWithoutBounds() {
        val screen = chatScreen(
            FakeNode(
                className = "android.widget.FrameLayout",
                children = listOf(
                    FakeNode(text = "no rectangle on this one", className = "android.widget.TextView"),
                ),
            ),
        )

        // No rectangle means we cannot tell incoming from outgoing, so we say
        // nothing rather than guess.
        assertNull(ScreenTextReader.readNewestMessage(screen, SCREEN_WIDTH))
    }

    @Test
    fun aFullWidthRowIsStillAMessage() {
        // The bug that made screen reading look switched off. A message row is
        // as wide as the list in every app this reader targets, so measuring
        // the row instead of the bubble rejected every message on screen.
        val screen = chatScreen(
            fullWidthRow("kalke meeting e ashbe?", top = 400, incoming = true),
        )

        val message = ScreenTextReader.readNewestMessage(screen, SCREEN_WIDTH)

        assertEquals("kalke meeting e ashbe?", message?.text)
        assertFalse(message!!.isOutgoing)
    }

    @Test
    fun aFullWidthOutgoingRowIsStillRecognisedAsSent() {
        val screen = chatScreen(
            fullWidthRow("haan, ashchi", top = 400, incoming = false),
        )

        val message = ScreenTextReader.readNewestMessage(screen, SCREEN_WIDTH)

        assertEquals("haan, ashchi", message?.text)
        assertTrue(message!!.isOutgoing)
    }

    @Test
    fun aFullWidthNodeThatIsNotABubbleIsStillRejected() {
        // The width test has not been thrown away, only moved onto the right
        // node: a notice spanning the screen is chrome in any app.
        val screen = chatScreen(
            FakeNode(
                className = "android.widget.FrameLayout",
                bounds = ScreenRect(0, 600, SCREEN_WIDTH, 700),
                children = listOf(
                    FakeNode(
                        text = "This chat is with a business account",
                        className = "android.widget.TextView",
                        bounds = ScreenRect(20, 610, SCREEN_WIDTH - 20, 680),
                    ),
                ),
            ),
        )

        assertNull(ScreenTextReader.readNewestMessage(screen, SCREEN_WIDTH))
    }

    @Test
    fun aShortReplyInAFullWidthRowIsNotTooSmallToRead() {
        // "ok" is a reply. A minimum width on the bubble swallowed exactly the
        // messages that are quickest to answer by hand.
        val screen = chatScreen(
            fullWidthRow("ok", top = 400, incoming = true),
        )

        val message = ScreenTextReader.readNewestMessage(screen, SCREEN_WIDTH)

        assertEquals("ok", message?.text)
    }

    @Test
    fun aScreenWithNoMessageListSaysSo() {
        // "It read nothing" is five failures; this is the first one, and the
        // report is how they get told apart on a phone.
        val screen = FakeNode(
            className = "android.widget.FrameLayout",
            children = listOf(
                FakeNode(text = "no list here", className = "android.widget.TextView"),
            ),
        )

        val result = ScreenTextReader.read(screen, SCREEN_WIDTH)

        assertEquals(ReadOutcome.NO_LIST, result.outcome)
        assertNull(result.message)
    }

    @Test
    fun aListWhoseRowsHoldNoTextSaysSo() {
        val screen = chatScreen(
            FakeNode(
                className = "android.widget.FrameLayout",
                bounds = ScreenRect(0, 200, SCREEN_WIDTH, 300),
            ),
        )

        assertEquals(
            ReadOutcome.NO_ROWS,
            ScreenTextReader.read(screen, SCREEN_WIDTH).outcome,
        )
    }

    @Test
    fun rowsThatHoldNoMessageSaySo() {
        // A list of timestamps: readable rows, nothing in them to answer.
        val screen = chatScreen(
            FakeNode(
                className = "android.widget.FrameLayout",
                bounds = ScreenRect(40, 200, 760, 300),
                children = listOf(
                    FakeNode(text = "10:42", className = "android.widget.TextView"),
                ),
            ),
        )

        assertEquals(
            ReadOutcome.NO_MESSAGE,
            ScreenTextReader.read(screen, SCREEN_WIDTH).outcome,
        )
    }

    @Test
    fun anOutgoingNewestMessageIsReportedAsOutgoing() {
        val result = ScreenTextReader.read(
            chatScreen(outgoingBubble("haan, ashchi")),
            SCREEN_WIDTH,
        )

        assertEquals(ReadOutcome.OUTGOING, result.outcome)
        assertEquals("haan, ashchi", result.message?.text)
    }

    @Test
    fun aGoodReadCountsWhatItWorkedWith() {
        val screen = chatScreen(
            incomingBubble("one", top = 200),
            incomingBubble("two", top = 340),
        )

        val result = ScreenTextReader.read(screen, SCREEN_WIDTH)

        assertEquals(ReadOutcome.READ, result.outcome)
        assertEquals(2, result.rowCount)
        assertEquals("two", result.message?.text)
    }
}
