package com.keshabstudios.replymate

/**
 * The one place a pending overlay context lives while the bubble is up.
 *
 * **Memory only, never persisted.** The map is held in the process heap and is
 * gone the moment the process dies. It is never written to SharedPreferences,
 * a file, a database, a cache, or a log - not on the way in, not on the way
 * out (docs/FLOATING_OVERLAY.md §5.2, docs/PRIVACY_AND_PERMISSIONS.md).
 *
 * Exactly one message is pending at a time: a newer notification replaces the
 * previous one, and [consume] both returns and clears it so the panel can never
 * read the same message twice.
 */
object OverlayBubbleController {

    /**
     * The pending context, or null when nothing is waiting. The map uses the
     * wire format of docs/PLATFORM_CHANNELS.md plus a `source` key
     * (`bubble` / `fallback`).
     */
    @Volatile
    private var pending: Map<String, Any?>? = null

    /** Replaces any previous pending context. A newer message always wins. */
    @Synchronized
    fun hold(context: Map<String, Any?>) {
        pending = context.toMap()
    }

    /** Returns the pending context and clears it - exactly once. */
    @Synchronized
    fun consume(): Map<String, Any?>? {
        val current = pending
        pending = null
        return current
    }

    /**
     * Reads the pending context without clearing it, for the service deciding
     * whether there is anything to draw and whether a removal belongs to the
     * bubble currently on screen. Callers that intend to *use* the context
     * must go through [consume].
     */
    @Synchronized
    fun peek(): Map<String, Any?>? = pending

    /** StatusBarNotification key of the pending message, when there is one. */
    fun pendingKey(): String? = peek()?.get("key") as? String

    /** Drops the pending context without handing it out (bubble dismissed). */
    @Synchronized
    fun clear() {
        pending = null
    }
}
