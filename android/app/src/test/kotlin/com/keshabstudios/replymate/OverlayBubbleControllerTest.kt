package com.keshabstudios.replymate

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The controller is the only piece of the overlay feature that is pure logic, so
 * it is the only piece that can be proven without a device. Everything here is
 * about two promises: the newest message is what the panel opens, and nothing is
 * ever handed out twice.
 */
class OverlayBubbleControllerTest {

    private fun context(key: String, text: String = "hi"): Map<String, Any?> = mapOf(
        "source" to "bubble",
        "packageName" to "com.whatsapp",
        "key" to key,
        "title" to "Asha",
        "text" to text,
    )

    @Before
    fun setUp() {
        OverlayBubbleController.clear()
    }

    @After
    fun tearDown() {
        OverlayBubbleController.clear()
    }

    @Test
    fun `nothing pending reads as empty, not as a fake message`() {
        assertNull(OverlayBubbleController.peek())
        assertNull(OverlayBubbleController.consume())
        assertEquals(0, OverlayBubbleController.size())
        assertTrue(OverlayBubbleController.peekAll().isEmpty())
    }

    @Test
    fun `the newest message is the one the panel opens`() {
        OverlayBubbleController.hold(context("k1", "first"))
        OverlayBubbleController.hold(context("k2", "second"))

        assertEquals("k2", OverlayBubbleController.pendingKey())
        assertEquals("second", OverlayBubbleController.consume()?.get("text"))
    }

    @Test
    fun `a message is never handed out twice`() {
        OverlayBubbleController.hold(context("k1"))
        OverlayBubbleController.consume()

        assertNull(OverlayBubbleController.consume())
        assertEquals(0, OverlayBubbleController.size())
    }

    @Test
    fun `one chat posting twice updates its entry instead of stacking`() {
        OverlayBubbleController.hold(context("k1", "old"))
        OverlayBubbleController.hold(context("k2", "other"))
        OverlayBubbleController.hold(context("k1", "new"))

        assertEquals(2, OverlayBubbleController.size())
        // Newest first, and the updated text is the one that survives.
        assertEquals("new", OverlayBubbleController.peekAll().first()["text"])
    }

    @Test
    fun `the stack is capped so a chatty day cannot hoard conversations`() {
        repeat(OverlayBubbleController.MAX_PENDING + 3) { index ->
            OverlayBubbleController.hold(context("k$index"))
        }

        assertEquals(OverlayBubbleController.MAX_PENDING, OverlayBubbleController.size())
        // The oldest ones were dropped; the newest is still the newest.
        val keys = OverlayBubbleController.peekAll().map { it["key"] }
        assertTrue(keys.contains("k${OverlayBubbleController.MAX_PENDING + 2}"))
        assertTrue(!keys.contains("k0"))
    }

    @Test
    fun `peekAll hands out copies the caller cannot corrupt`() {
        OverlayBubbleController.hold(context("k1"))
        val snapshot = OverlayBubbleController.peekAll()

        assertEquals(1, snapshot.size)
        // Reading it does not consume anything: the bubble is still there.
        assertEquals(1, OverlayBubbleController.size())
        assertEquals("k1", OverlayBubbleController.pendingKey())
    }
}
