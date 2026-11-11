package com.keshabstudios.replymate

import android.content.Context

/**
 * The packages the user selected on the app-selection screen, read the same way
 * by every message source.
 *
 * Both the notification listener and the screen reader ask this before looking
 * at anything, because the allowlist is the user's decision about which apps
 * ReplyMate may see at all - and a second copy of that rule is a second chance
 * to get it wrong.
 */
object AppAllowlist {

    fun contains(context: Context, packageName: String): Boolean {
        if (packageName.isBlank()) return false
        return all(context).contains(packageName)
    }

    /** The allowlist as the user left it, so Settings can show it back. */
    fun all(context: Context): List<String> {
        val allowed = context
            .getSharedPreferences(ReplyMateNotificationListener.PREFS_NAME, Context.MODE_PRIVATE)
            .getStringSet(ReplyMateNotificationListener.KEY_ALLOWED_PACKAGES, emptySet())
            ?: emptySet()
        return allowed.sorted()
    }
}
