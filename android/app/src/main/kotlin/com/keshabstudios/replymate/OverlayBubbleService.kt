package com.keshabstudios.replymate

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView

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
    private var badgeView: TextView? = null
    private var iconView: ImageView? = null

    /**
     * True while the bubble is tucked against a screen edge as a slim tab.
     * Tapping the tab brings the bubble back; a new message does it too, so a
     * hidden bubble never makes the user miss something.
     */
    private var collapsed = false

    /** Notification key currently represented by the bubble. */
    private var shownKey: String? = null

    /** How many messages arrived while this bubble has been on screen. */
    private var messagesWhileShowing = 0

    private val handler = Handler(Looper.getMainLooper())
    private var screenReceiver: BroadcastReceiver? = null

    /** A bubble nobody uses should not sit on the screen forever. */
    private val autoHide = Runnable {
        OverlayBubbleController.clear()
        stopSelf()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(OVERLAY_NOTIFICATION_ID, buildNotification())
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        isShowing = true
        registerScreenReceiver()
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
        val key = OverlayBubbleController.pendingKey()
        if (bubbleView != null) {
            // Already drawn: a newer message updates the badge instead of
            // stacking a second bubble nobody asked for.
            if (key != null && key != shownKey) {
                shownKey = key
                messagesWhileShowing += 1
                // A message the user has not seen is worth interrupting for,
                // even if they had tucked the bubble away.
                if (collapsed) expand()
                updateBadge()
            }
            return
        }
        val manager = windowManager ?: return
        val view = createBubbleView()
        val params = createLayoutParams()
        try {
            manager.addView(view, params)
            bubbleView = view
            layoutParams = params
            shownKey = key
            messagesWhileShowing = 1
            updateBadge()
            scheduleAutoHide()
        } catch (error: Exception) {
            // A refused window (permission race, OEM quirk) must not take the
            // process down: nothing is drawn and the fallback notification is
            // what the user gets.
            removeBubble()
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoHide)
        unregisterScreenReceiver()
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
        // Message count, shown only when a second message arrives while the
        // bubble is up: one bubble, an honest count, never a stack of views.
        val badge = TextView(this)
        badge.setTextColor(Color.WHITE)
        badge.textSize = 11f
        badge.gravity = Gravity.CENTER
        badge.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(badgeColor())
            setStroke(dp(1), Color.WHITE)
        }
        badge.visibility = View.GONE
        val badgeSize = dp(20)
        root.addView(
            badge,
            FrameLayout.LayoutParams(badgeSize, badgeSize).apply {
                gravity = Gravity.TOP or Gravity.END
            },
        )
        badgeView = badge
        iconView = icon

        root.setOnTouchListener(DragToTapListener())
        return root
    }

    private fun updateBadge() {
        val badge = badgeView ?: return
        if (messagesWhileShowing > 1) {
            badge.text = if (messagesWhileShowing > 9) "9+" else messagesWhileShowing.toString()
            badge.visibility = View.VISIBLE
        } else {
            badge.visibility = View.GONE
        }
    }

    private fun scheduleAutoHide() {
        handler.removeCallbacks(autoHide)
        handler.postDelayed(autoHide, AUTO_HIDE_MILLIS)
    }

    /**
     * Leaving a bubble on a screen the user has turned off (or locked) is both
     * pointless and a privacy leak on the lock screen: it goes away, and comes
     * back on unlock while the message is still pending.
     */
    private fun registerScreenReceiver() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> removeBubble()
                    Intent.ACTION_USER_PRESENT -> show()
                }
            }
        }
        screenReceiver = receiver
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // Our own receiver, never exported.
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }
        } catch (error: Exception) {
            screenReceiver = null
        }
    }

    private fun unregisterScreenReceiver() {
        val receiver = screenReceiver ?: return
        screenReceiver = null
        try {
            unregisterReceiver(receiver)
        } catch (error: Exception) {
            // Already unregistered.
        }
    }

    /**
     * Restyles the same view for its two states. Nothing is re-added to the
     * window: a collapse is a resize, so a tap that arrives mid-animation still
     * lands on a live view.
     */
    private fun applyBubbleAppearance(view: View, collapsed: Boolean) {
        val root = view as? FrameLayout ?: return
        val size = resources.getDimensionPixelSize(R.dimen.overlay_bubble_size)
        val tabWidth = resources.getDimensionPixelSize(R.dimen.overlay_bubble_collapsed_width)
        root.background = GradientDrawable().apply {
            setColor(bubbleColor())
            setStroke(dp(2), Color.WHITE)
            if (collapsed) {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = tabWidth / 2f
            } else {
                shape = GradientDrawable.OVAL
            }
        }
        iconView?.setPadding(
            if (collapsed) dp(4) else size / 4,
            if (collapsed) dp(4) else size / 4,
            if (collapsed) dp(4) else size / 4,
            if (collapsed) dp(4) else size / 4,
        )
        if (collapsed) {
            // The count would be clipped to nothing on a 22dp tab, and the
            // expanded state calls updateBadge() to restore it.
            badgeView?.visibility = View.GONE
        }
        root.contentDescription = getString(
            if (collapsed) {
                R.string.overlay_bubble_description_collapsed
            } else {
                R.string.overlay_bubble_description
            },
        )
    }

    /** Tucks the bubble against [toRight] edge as a slim, still-tappable tab. */
    private fun collapse(toRight: Boolean) {
        val params = layoutParams ?: return
        val view = bubbleView ?: return
        val size = resources.getDimensionPixelSize(R.dimen.overlay_bubble_size)
        val tabWidth = resources.getDimensionPixelSize(R.dimen.overlay_bubble_collapsed_width)
        val metrics = resources.displayMetrics
        collapsed = true
        params.width = tabWidth
        params.height = size
        params.x = if (toRight) metrics.widthPixels - tabWidth else 0
        applyBubbleAppearance(view, collapsed = true)
        try {
            windowManager?.updateViewLayout(view, params)
        } catch (error: Exception) {
            // The window went away; nothing to tuck.
            collapsed = false
        }
    }

    /** Brings a tucked bubble back to full size on the edge it was hiding on. */
    private fun expand() {
        val params = layoutParams ?: return
        val view = bubbleView ?: return
        val size = resources.getDimensionPixelSize(R.dimen.overlay_bubble_size)
        val metrics = resources.displayMetrics
        val onRight = params.x > metrics.widthPixels / 2
        collapsed = false
        params.width = size
        params.height = size
        params.x = if (onRight) metrics.widthPixels - size else 0
        applyBubbleAppearance(view, collapsed = false)
        try {
            windowManager?.updateViewLayout(view, params)
        } catch (error: Exception) {
            // Ignore: the view is gone and show() will rebuild it.
        }
        updateBadge()
        rememberPosition(params)
    }

    /**
     * Where the finger left the bubble decides its home: within a thumb of an
     * edge it tucks itself away there, anywhere else it just stays put.
     */
    private fun settleAfterDrag(params: WindowManager.LayoutParams) {
        val metrics = resources.displayMetrics
        val edgeZone = dp(28)
        when {
            params.x <= edgeZone -> collapse(toRight = false)
            params.x + params.width >= metrics.widthPixels - edgeZone ->
                collapse(toRight = true)
            else -> {
                rememberPosition(params)
                // A tab dragged into the middle of the screen would just look
                // broken, so letting go of it restores the full bubble.
                if (collapsed) expand()
            }
        }
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
            // Where the user dragged it last time, clamped to the screen so a
            // remembered position from a bigger display cannot park the bubble
            // off-screen. Nothing here is message content - two integers.
            val defaults = prefs()
            val metrics = resources.displayMetrics
            x = defaults.getInt(
                KEY_BUBBLE_X,
                resources.getDimensionPixelSize(R.dimen.overlay_bubble_default_x),
            ).coerceIn(0, maxOf(0, metrics.widthPixels - size))
            y = defaults.getInt(
                KEY_BUBBLE_Y,
                resources.getDimensionPixelSize(R.dimen.overlay_bubble_default_y),
            ).coerceIn(0, maxOf(0, metrics.heightPixels - size))
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
                    if (dragging) {
                        settleAfterDrag(params)
                    } else if (collapsed) {
                        // A tucked bubble comes back first; the panel is the
                        // second tap, so hiding it can never fire an action by
                        // accident.
                        expand()
                    } else {
                        openPanel()
                    }
                    return true
                }
                MotionEvent.ACTION_CANCEL -> return true
            }
            return false
        }
    }

    /**
     * Remembers where the bubble was dropped, so the next one appears where the
     * user expects it instead of jumping back to the default corner. Position
     * only: two integers, no message, no sender
     * (docs/FLOATING_OVERLAY.md §5.2).
     */
    private fun rememberPosition(params: WindowManager.LayoutParams) {
        try {
            prefs().edit()
                .putInt(KEY_BUBBLE_X, params.x)
                .putInt(KEY_BUBBLE_Y, params.y)
                .apply()
        } catch (error: Exception) {
            // Losing a position is not worth a crash.
        }
    }

    private fun prefs() =
        getSharedPreferences(ReplyMateNotificationListener.PREFS_NAME, MODE_PRIVATE)

    /**
     * Opens the panel. The context is **not** consumed here: the activity
     * consumes it exactly once, so a failed launch leaves the message pending
     * for the next attempt instead of dropping it.
     */
    private fun openPanel() {
        val intent = OverlayPanelActivity.createIntent(this)
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
        badgeView = null
        iconView = null
        collapsed = false
        shownKey = null
        messagesWhileShowing = 0
        handler.removeCallbacks(autoHide)
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

    private fun badgeColor(): Int = getColor(R.color.overlay_fallback_accent)

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        /** docs/FLOATING_OVERLAY.md §5.3: a bubble nobody uses goes away. */
        private const val AUTO_HIDE_MILLIS = 10 * 60 * 1000L

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
                if (isShowing) {
                    // Already a running foreground service: this only delivers
                    // onStartCommand, which is allowed from the background and
                    // is the path a newly posted notification takes.
                    context.startService(intent)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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

        /** Last drag position of the bubble, in pixels. */
        private const val KEY_BUBBLE_X = "bubble_x"
        private const val KEY_BUBBLE_Y = "bubble_y"
    }
}
