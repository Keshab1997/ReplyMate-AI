package com.keshabstudios.replymate

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings

/**
 * The one decision both message sources share: raise the bubble, or post the
 * honest fallback.
 *
 * The notification listener and the screen reader reach this object separately
 * because they see different things - one sees a posted notification, the
 * other sees the chat the user is already looking at, where no notification is
 * ever posted. The moment the message is known, the rest of the decision is
 * identical, and two copies of it would drift the first time either one was
 * fixed (docs/FLOATING_OVERLAY.md §5.3).
 *
 * The user's bubble switch governs both surfaces: switched off means neither
 * appears - the app does not nag (docs/FLOATING_OVERLAY.md §8).
 */
object OverlayRouter {

    /** The `source` values the Dart side reads (docs/PLATFORM_CHANNELS.md). */
    const val SOURCE_BUBBLE = "bubble"
    const val SOURCE_FALLBACK = "fallback"

    private const val SOURCE_KEY = "source"

    /**
     * Fallback notification channel: the honest path when the bubble cannot be
     * drawn. Low importance, because it is a shortcut, not an alarm.
     */
    private const val FALLBACK_CHANNEL_ID = "replymate_fallback"

    /**
     * Bubble first, fallback second - never both, never a crash.
     *
     * Degraded path 1: no overlay permission.
     * Degraded path 2: Android 12+ refused a foreground-service start because
     * this process is in the background - documented, not a bug
     * (docs/FLOATING_OVERLAY.md §7).
     */
    fun route(context: Context, parsed: Map<String, Any?>) {
        if (!OverlayBubbleService.isEnabledByUser(context)) return
        if (!isScreenOnAndUnlocked(context)) return

        if (!Settings.canDrawOverlays(context)) {
            showFallback(context, parsed)
            return
        }

        OverlayBubbleController.hold(parsed + (SOURCE_KEY to SOURCE_BUBBLE))
        if (!OverlayBubbleService.start(context)) {
            showFallback(context, parsed)
        }
    }

    private fun showFallback(context: Context, parsed: Map<String, Any?>) {
        OverlayBubbleController.hold(parsed + (SOURCE_KEY to SOURCE_FALLBACK))
        val packageName = parsed["packageName"] as? String ?: return
        postFallbackNotification(context, packageName)
    }

    /**
     * The screen is on and unlocked. A bubble over the lock screen is a bubble
     * over someone else's business, and a message read while the screen is off
     * is not a message the user is looking at.
     */
    fun isScreenOnAndUnlocked(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
        if (power != null && !power.isInteractive) return false
        val keyguard =
            context.getSystemService(Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
        return keyguard?.isKeyguardLocked != true
    }

    /**
     * One notification per package, replaced rather than stacked, and it never
     * carries the message text - the app name is the whole promise
     * (docs/PRIVACY_AND_PERMISSIONS.md).
     */
    private fun postFallbackNotification(context: Context, packageName: String) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        createFallbackChannel(context, manager)

        val intent = Intent(context, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OVERLAY_PANEL
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            packageName.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, FALLBACK_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(
                context.getString(
                    R.string.overlay_fallback_title,
                    appLabel(context, packageName),
                ),
            )
            .setContentText(context.getString(R.string.overlay_fallback_text))
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .build()
        try {
            manager.notify(packageName.hashCode(), notification)
        } catch (error: Exception) {
            // Notifications denied on Android 13+: the bubble path already said
            // what it could. Never crash a message source over a notification.
        }
    }

    private fun createFallbackChannel(context: Context, manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            FALLBACK_CHANNEL_ID,
            context.getString(R.string.overlay_fallback_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = context.getString(R.string.overlay_fallback_channel_description)
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
    }

    /** The app's own name, or its package id when Android will not tell us. */
    fun appLabel(context: Context, packageName: String): String = try {
        context.packageManager.getApplicationLabel(
            context.packageManager.getApplicationInfo(packageName, 0),
        ).toString()
    } catch (error: Exception) {
        packageName
    }
}
