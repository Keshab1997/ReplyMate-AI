package com.keshabstudios.replymate

/**
 * The one place a pending overlay context lives while the bubble is up.
 *
 * **Memory only, never persisted.** The map is held in the process heap and is
 * gone the moment the process dies. It is never written to SharedPreferences,
 * a file, a database, a cache, or a log - not on the way in, not on the way
 * out.md §5.2,.md).
 *
 * Up to [MAX_PENDING] messages are kept, because three chats can ping you while
 * the bubble is on screen and collapsing them into one meant the panel could
 * only ever answer the last one. They are keyed by notification key, so a chat
 * that posts twice updates its entry instead of stacking a duplicate, and the
 * oldest is dropped when the cap is reached - a bubble that remembers ten
 * conversations is a bubble that hoards.
 *
 * [consume] returns and removes the newest, so the panel still cannot read the
 * same message twice.
 */
object OverlayBubbleController {

    /**
     * The pending context, or null when nothing is waiting. The map uses the
     * wire format of.md plus a `source` key
     * (`bubble` / `fallback`).
     */
    const val MAX_PENDING = 5

    /**
     * Newest last: a `LinkedHashMap` keeps arrival order, which is the order the
     * panel shows and the order [consume] walks from the end.
     */
    private val pending = LinkedHashMap<String, Map<String, Any?>>()

    /**
     * Bumped on every [hold]. Callers cannot tell "a second message from a
     * different chat" from "a second message from the same chat" by looking at
     * [size] - a re-post updates its own entry and the count stays at one - so
     * the bubble watches this number instead. A counter, not a timestamp: it
     * carries nothing about the message, which keeps this object inside its
     * rule that the heap holds context and nothing else.
     */
    private var revisionCounter = 0L

    /** Monotonic: changes whenever [hold] stores anything at all. */
    @Synchronized
    fun revision(): Long = revisionCounter

    /** Adds or refreshes a context. A newer message always wins its slot. */
    @Synchronized
    fun hold(context: Map<String, Any?>) {
        val copy = context.toMap()
        val key = copy["key"] as? String ?: copy.hashCode().toString()
        pending.remove(key)
        pending[key] = copy
        revisionCounter++
        while (pending.size > MAX_PENDING) {
            val oldest = pending.keys.firstOrNull() ?: break
            pending.remove(oldest)
        }
    }

    /** Returns the newest context and removes it - exactly once. */
    @Synchronized
    fun consume(): Map<String, Any?>? {
        val newest = pending.keys.lastOrNull() ?: return null
        return pending.remove(newest)
    }

    /**
     * Reads the newest context without clearing it, for the service deciding
     * whether there is anything to draw and whether a removal belongs to the
     * bubble currently on screen. Callers that intend to *use* the context
     * must go through [consume].
     */
    @Synchronized
    fun peek(): Map<String, Any?>? = pending.values.lastOrNull()

    /**
     * Every pending context, newest first, for the panel's chat switcher.
     * Copies, so a caller cannot mutate what is held here.
     */
    @Synchronized
    fun peekAll(): List<Map<String, Any?>> =
        pending.values.reversed().map { it.toMap() }

    /** How many messages are waiting: the bubble's badge is this number. */
    @Synchronized
    fun size(): Int = pending.size

    /** StatusBarNotification key of the newest message, when there is one. */
    fun pendingKey(): String? = peek()?.get("key") as? String

    /** Drops every pending context without handing one out (bubble dismissed). */
    @Synchronized
    fun clear() {
        pending.clear()
    }

    /** Drops one context, for a notification that was withdrawn. */
    @Synchronized
    fun remove(key: String) {
        pending.remove(key)
    }
}
