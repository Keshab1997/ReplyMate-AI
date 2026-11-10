package com.keshabstudios.replymate

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo

/**
 * The platform adapter between Android's live accessibility tree and the pure
 * [ScreenNode] shape [ScreenTextReader] reads.
 *
 * It is the only file in the screen-reading feature that touches Android, and
 * that is the point: the heuristics live in a file a plain JVM can compile and
 * test (see `ScreenTextReaderTest.kt`), while this one only translates.
 *
 * The tree is walked synchronously, inside the event callback, and the root is
 * recycled by the caller. Children are read once and held as [AndroidScreenNode]
 * values for the duration of that walk; nothing is cached afterwards, and no
 * text is ever copied anywhere but the reader's return value.
 */
class AndroidScreenNode(
    private val node: AccessibilityNodeInfo,
) : ScreenNode {

    override val text: String?
        get() = node.text?.toString()

    override val viewId: String?
        get() = node.viewIdResourceName

    override val className: String?
        get() = node.className?.toString()

    /**
     * The node's rectangle on screen, or null when Android reported nothing.
     *
     * A view that is off-screen or has no size reports an all-zero rectangle,
     * and an all-zero rectangle is not evidence of anything - the reader
     * refuses to guess left from right without it.
     */
    override val bounds: ScreenRect?
        get() {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            if (rect.left == 0 && rect.top == 0 && rect.right == 0 && rect.bottom == 0) {
                return null
            }
            return ScreenRect(rect.left, rect.top, rect.right, rect.bottom)
        }

    override val children: List<ScreenNode>
        get() {
            val count = node.childCount
            if (count <= 0) return emptyList()
            val children = ArrayList<ScreenNode>(count)
            for (index in 0 until count) {
                val child = node.getChild(index) ?: continue
                children.add(AndroidScreenNode(child))
            }
            return children
        }
}
