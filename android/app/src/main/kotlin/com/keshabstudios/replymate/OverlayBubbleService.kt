package com.keshabstudios.replymate

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView

/**
 * Draws the one thing Flutter cannot draw here: a bubble over *another* app.
 *
 * The Flutter engine only exists while one of our activities is alive, which is
 * exactly the case this feature has to cover, so the bubble is a plain
 * `WindowManager` view owned by a foreground service
 * (docs/FLOATING_OVERLAY.md §4.1).
 *
 * What this service deliberately does **not** do:
 *  - read the screen, the app underneath, or any accessibility node (it only
 *    knows what the notification posted);
 *  - show the sender or the message text - the bubble is an icon;
 *  - persist or log the pending message (it lives in
 *    [OverlayBubbleController], memory only);
 *  - send anything by itself.
 *
 * Android 12+ forbids starting a foreground service from the background, so
 * [start] reports failure instead of crashing and the caller posts the
 * documented fallback notification (docs/FLOATING_OVERLAY.md §7).
 */
class OverlayBubbleService : Service() {

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(OVERLAY_NOTIFICATION_ID, buildNotification())
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        isShowing = true
        // A pending context is normally held before the service starts; drawing
        // here covers the case where the service outlived a hide/show cycle.
        show()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        show()
        return START_NOT_STICKY
    }

    /**
     * Attaches the bubble when a message is pending, and does nothing at all
     * when there is none: a bubble with no message behind it would be a lie the
     * user cannot get rid of.
     */
    fun show() {
        if (OverlayBubbleController.peek() == null) {
            removeBubble()
            return
        }
        if (!Settings.canDrawOverlays(this)) {
            // Permission revoked while we were alive; the fallback path takes
            // over from here.
            removeBubble()
            stopSelf()
            return
        }
        if (bubbleView != null) return
        val manager = windowManager ?: return
        val view = createBubbleView()
        val params = createLayoutParams()
        try {
            manager.addView(view, params)
            bubbleView = view
            layoutParams = params
        } catch (error: Exception) {
            // A refused window (permission race, OEM quirk) must not take the
            // process down: nothing is drawn and the fallback notification is
            // what the user gets.
            removeBubble()
        }
    }

    override fun onDestroy() {
        removeBubble()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        isShowing = false
        super.onDestroy()
    }

    // ---------------------------------------------------------------- view

    private fun createBubbleView(): View {
        val size = resources.getDimensionPixelSize(R.dimen.overlay_bubble_size)
        val root = FrameLayout(this)
        root.contentDescription = getString(R.string.overlay_bubble_description)
        root.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(bubbleColor())
            setStroke(dp(2), Color.WHITE)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            root.elevation = dp(6).toFloat()
        }

        // Placeholder glyph until the app has its own icon: the launcher icon
        // is honest about what the bubble belongs to.
        val icon = ImageView(this)
        icon.setImageResource(R.mipmap.ic_launcher)
        icon.setPadding(size / 4, size / 4, size / 4, size / 4)
        root.addView(
            icon,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        root.setOnTouchListener(DragToTapListener())
        return root
    }

    private fun createLayoutParams(): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val size = resources.getDimensionPixelSize(R.dimen.overlay_bubble_size)
        return WindowManager.LayoutParams(
            size,
            size,
            type,
            // Not focusable: taps reach the app underneath everywhere except
            // the bubble itself, so dragging and tapping stay unambiguous.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = resources.getDimensionPixelSize(R.dimen.overlay_bubble_default_x)
            y = resources.getDimensionPixelSize(R.dimen.overlay_bubble_default_y)
        }
    }

    /**
     * Drag moves the bubble; a touch that stays inside the touch slop is a
     * tap. Distinguishing them by movement (not by time) is what makes the
     * bubble feel like a bubble instead of a button that sometimes opens a
     * panel when the user meant to move it.
     */
    private inner class DragToTapListener : View.OnTouchListener {
        private val touchSlop = ViewConfiguration.get(this@OverlayBubbleService)
            .scaledTouchSlop
        private var downRawX = 0f
        private var downRawY = 0f
        private var startX = 0
        private var startY = 0
        private var dragging = false

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val params = layoutParams ?: return false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startX = params.x
                    startY = params.y
                    dragging = false
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (!dragging && (Math.abs(dx) > touchSlop || Math.abs(dy) > touchSlop)) {
                        dragging = true
                    }
                    if (dragging) {
                        params.x = startX + dx.toInt()
                        params.y = startY + dy.toInt()
                        try {
                            windowManager?.updateViewLayout(view, params)
                        } catch (error: Exception) {
                            // The window went away mid-drag; nothing to save.
                        }
                    }
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    if (!dragging) openPanel()
                    return true
                }
                MotionEvent.ACTION_CANCEL -> return true
            }
            return false
        }
    }

    /**
     * Opens the panel. The context is **not** consumed here: the activity
     * consumes it exactly once, so a failed launch leaves the message pending
     * for the next attempt instead of dropping it.
     */
    private fun openPanel() {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OVERLAY_PANEL
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }
        try {
            startActivity(intent)
        } catch (error: Exception) {
            // No activity to open (rare, but a crash here would look like a
            // broken bubble); keep the bubble so the user can try again.
            return
        }
        // The panel replaces the bubble (docs/FLOATING_OVERLAY.md §5.3).
        stopSelf()
    }

    private fun removeBubble() {
        val view = bubbleView
        val manager = windowManager
        bubbleView = null
        layoutParams = null
        if (view != null && manager != null) {
            try {
                manager.removeView(view)
            } catch (error: Exception) {
                // Already detached: nothing to remove.
            }
        }
    }

    // -------------------------------------------------------- notification

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.overlay_channel_name),
            // Anything above MIN would put a permanent, noisy entry in the
            // shade for a feature the user may only use occasionally.
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            description = getString(R.string.overlay_channel_description)
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    /** The service's own notification. It names the feature, never a message. */
    @Suppress("DEPRECATION")
    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.overlay_notification_title))
            .setContentText(getString(R.string.overlay_notification_text))
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(openAppIntent())
            .build()
    }

    private fun openAppIntent(): PendingIntent? {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(
            this,
            OVERLAY_NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * Bubble background. A resource, not a theme attribute: this service has no
     * appcompat theme, and looking up an attribute the theme does not define
     * would fail at runtime on exactly the devices the bubble is for.
     */
    private fun bubbleColor(): Int = getColor(R.color.overlay_bubble_background)

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        /** Fixed id: one bubble notification, replaced rather than stacked. */
        const val OVERLAY_NOTIFICATION_ID = 4211
        const val CHANNEL_ID = "replymate_bubble"

        /** True while the service is alive and therefore bindable. */
        @Volatile
        var isShowing: Boolean = false
            private set

        /**
         * Starts the bubble service, or reports that it cannot start.
         *
         * `false` means "no bubble right now" - the overlay permission is
         * missing, or Android refused a foreground-service start from the
         * background (`ForegroundServiceStartNotAllowedException`, Android
         * 12+). The caller posts the fallback notification instead; nothing
         * here crashes.
         */
        fun start(context: Context): Boolean {
            if (!Settings.canDrawOverlays(context)) return false
            val intent = Intent(context, OverlayBubbleService::class.java)
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (error: Exception) {
                // Includes ForegroundServiceStartNotAllowedException (API 31+),
                // caught as Exception so the class reference cannot break
                // older devices. The documented degraded path applies.
                false
            }
        }

        /** Stops the bubble and removes its view. Safe to call when not running. */
        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, OverlayBubbleService::class.java))
            } catch (error: Exception) {
                // Already gone.
            }
        }

        /** The user's bubble switch, persisted natively for the listener. */
        fun isEnabledByUser(context: Context): Boolean =
            context.getSharedPreferences(ReplyMateNotificationListener.PREFS_NAME, MODE_PRIVATE)
                .getBoolean(KEY_BUBBLE_ENABLED, false)

        fun setEnabledByUser(context: Context, enabled: Boolean) {
            context.getSharedPreferences(ReplyMateNotificationListener.PREFS_NAME, MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_BUBBLE_ENABLED, enabled)
                .apply()
        }

        /** Default off: the switch only matters once overlay access is granted. */
        const val KEY_BUBBLE_ENABLED = "bubble_enabled"
    }
}
