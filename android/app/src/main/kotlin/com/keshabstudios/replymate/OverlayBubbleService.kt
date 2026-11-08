package com.keshabstudios.replymate

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.animation.ValueAnimator
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
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
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
    private var gripView: LinearLayout? = null

    /** Drives the idle bob; null while tucked, dragging or behind the panel. */
    private var bobAnimator: ValueAnimator? = null

    /** True while the reply panel is on screen. The bubble steps aside for it. */
    private var panelOpen = false

    /**
     * The context the open panel is working from. Kept so the bubble survives a
     * panel session: the panel consumes the pending context, and without this
     * the bubble would die the first time the user replied - which is exactly
     * what made "reply, then reply again" impossible.
     *
     * Memory only, like the controller itself: never written anywhere.
     */
    private var panelContext: Map<String, Any?>? = null

    private var panelReceiver: BroadcastReceiver? = null

    /** The long-press menu window, when it is open. */
    private var menuView: View? = null

    /**
     * Fires when a finger stays still on the bubble. Dragging cancels it, so a
     * slow drag never opens the menu by accident.
     */
    private var longPressRunnable: Runnable? = null

    /** Auto-closes the menu: a menu nobody touches should not sit on screen. */
    private var menuTimeout: Runnable? = null

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
        registerPanelReceiver()
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
                // The badge is the real number of waiting chats, not a tap
                // counter: three chats pinging you must say three.
                messagesWhileShowing = OverlayBubbleController.size()
                // A message the user has not seen is worth interrupting for,
                // even if they had tucked the bubble away.
                if (collapsed) {
                    expand()
                } else {
                    pulseOnce()
                }
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
            messagesWhileShowing = maxOf(1, OverlayBubbleController.size())
            updateBadge()
            startIdleAnimation()
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
        stopIdleAnimation()
        unregisterScreenReceiver()
        unregisterPanelReceiver()
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

        // The 3D helper face (design/bubble_preview.html). It is drawn by the
        // artwork itself, so the bubble needs no extra ring or glyph: the
        // GradientDrawable above stays as the fallback the tab state uses.
        val icon = ImageView(this)
        icon.setImageResource(R.drawable.overlay_bubble_mascot)
        icon.scaleType = ImageView.ScaleType.CENTER_CROP
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

        // Tucked state: the face is gone and three dots say "pull me back".
        val grip = LinearLayout(this)
        grip.orientation = LinearLayout.VERTICAL
        grip.gravity = Gravity.CENTER
        grip.visibility = View.GONE
        repeat(3) {
            val dot = View(this)
            dot.setBackgroundColor(Color.WHITE)
            grip.addView(
                dot,
                LinearLayout.LayoutParams(dp(4), dp(4)).apply {
                    topMargin = if (it == 0) 0 else dp(3)
                },
            )
        }
        root.addView(
            grip,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        gripView = grip

        root.setOnTouchListener(DragToTapListener())
        return root
    }

    /**
     * The face bobs gently and blinks now and then. Both are ordinary property
     * animations on a view that already exists: no frame assets, no Lottie, no
     * battery cost worth mentioning, and nothing that can throw while the
     * window is going away.
     */
    private fun startIdleAnimation() {
        stopIdleAnimation()
        val icon = iconView ?: return
        val amplitude = dp(2).toFloat()
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1_500L
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            interpolator = LinearInterpolator()
            addUpdateListener { animation ->
                icon.translationY =
                    (animation.animatedValue as Float) * amplitude - amplitude / 2f
            }
        }
        animator.start()
        bobAnimator = animator
        scheduleBlink()
    }

    private fun stopIdleAnimation() {
        bobAnimator?.cancel()
        bobAnimator = null
        handler.removeCallbacks(blinkRunnable)
        iconView?.let {
            it.translationY = 0f
            it.scaleY = 1f
        }
    }

    /**
     * A blink is a 90ms squash of the face. Irregular timing keeps it from
     * reading as a metronome.
     */
    private val blinkRunnable = object : Runnable {
        override fun run() {
            val icon = iconView
            if (icon != null && !collapsed && !panelOpen) {
                icon.animate()
                    .scaleY(0.12f)
                    .setDuration(90L)
                    .withEndAction {
                        icon.animate().scaleY(1f).setDuration(120L).start()
                    }
                    .start()
            }
            scheduleBlink()
        }
    }

    private fun scheduleBlink() {
        handler.removeCallbacks(blinkRunnable)
        handler.postDelayed(blinkRunnable, 3_500L + (Math.random() * 3_000L).toLong())
    }

    /** New message: one soft pop plus a tap of haptic feedback. */
    private fun pulseOnce() {
        val view = bubbleView ?: return
        if (collapsed || panelOpen) return
        view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        view.animate()
            .scaleX(1.1f)
            .scaleY(1.1f)
            .setDuration(160L)
            .withEndAction {
                view.animate().scaleX(1f).scaleY(1f).setDuration(200L).start()
            }
            .start()
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
        iconView?.visibility = if (collapsed) View.GONE else View.VISIBLE
        gripView?.visibility = if (collapsed) View.VISIBLE else View.GONE
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
        stopIdleAnimation()
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
        startIdleAnimation()
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
    private fun scheduleLongPress(onFired: () -> Unit) {
        cancelLongPress()
        if (collapsed) return
        val runnable = Runnable { onFired() }
        longPressRunnable = runnable
        handler.postDelayed(runnable, LONG_PRESS_MILLIS)
    }

    private fun cancelLongPress() {
        longPressRunnable?.let { handler.removeCallbacks(it) }
        longPressRunnable = null
    }

    /**
     * The bubble's second door. Dragging to the edge and waiting for the
     * notification both hide the bubble, but neither is discoverable; a long
     * press is the gesture people try on anything round.
     *
     * Three actions, no text of the message anywhere: reply, tuck away, dismiss.
     */
    private fun showMenu() {
        val anchor = layoutParams ?: return
        val manager = windowManager ?: return
        if (menuView != null || panelOpen) return
        bubbleView?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)

        val card = LinearLayout(this)
        card.orientation = LinearLayout.VERTICAL
        card.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(14).toFloat()
            setColor(menuBackgroundColor())
        }
        card.elevation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            dp(10).toFloat()
        } else {
            0f
        }
        card.addView(menuRow(R.string.overlay_bubble_menu_reply) { openPanel() })
        card.addView(menuRow(R.string.overlay_bubble_menu_hide) {
            collapse(toRight = anchor.x > resources.displayMetrics.widthPixels / 2)
        })
        card.addView(menuRow(R.string.overlay_bubble_menu_dismiss) { dismissBubble() })

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val width = dp(168)
        val height = dp(3 * 44)
        val metrics = resources.displayMetrics
        val params = WindowManager.LayoutParams(
            width,
            height,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = if (anchor.x + anchor.width + width + dp(8) <= metrics.widthPixels) {
                anchor.x + anchor.width + dp(8)
            } else {
                (anchor.x - width - dp(8)).coerceAtLeast(0)
            }
            y = anchor.y.coerceIn(dp(8), maxOf(dp(8), metrics.heightPixels - height - dp(8)))
        }
        try {
            manager.addView(card, params)
            menuView = card
            menuTimeout?.let { handler.removeCallbacks(it) }
            val timeout = Runnable { hideMenu() }
            menuTimeout = timeout
            handler.postDelayed(timeout, MENU_TIMEOUT_MILLIS)
        } catch (error: Exception) {
            // A refused menu window must never take the bubble down with it.
            menuView = null
        }
    }

    private fun menuRow(labelRes: Int, action: () -> Unit): View {
        val row = TextView(this)
        row.text = getString(labelRes)
        row.setTextColor(Color.WHITE)
        row.textSize = 14f
        row.gravity = Gravity.CENTER_VERTICAL
        row.setPadding(dp(16), 0, dp(16), 0)
        row.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(44),
        )
        row.setOnClickListener {
            hideMenu()
            action()
        }
        return row
    }

    private fun hideMenu() {
        menuTimeout?.let { handler.removeCallbacks(it) }
        menuTimeout = null
        val view = menuView
        val manager = windowManager
        menuView = null
        if (view != null && manager != null) {
            try {
                manager.removeView(view)
            } catch (error: Exception) {
                // Already gone.
            }
        }
    }

    /** Dismiss is the user saying "not now" - it means the bubble and its
     *  pending message both go (docs/FLOATING_OVERLAY.md §5.3). */
    private fun dismissBubble() {
        hideMenu()
        OverlayBubbleController.clear()
        removeBubble()
        stopSelf()
    }

    private inner class DragToTapListener : View.OnTouchListener {
        private val touchSlop = ViewConfiguration.get(this@OverlayBubbleService)
            .scaledTouchSlop
        private var downRawX = 0f
        private var downRawY = 0f
        private var startX = 0
        private var startY = 0
        private var dragging = false

        /**
         * True once this gesture's long press has opened the menu: the release
         * that follows must not be read as "close the menu I just opened".
         */
        private var longPressFired = false

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val params = layoutParams ?: return false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startX = params.x
                    startY = params.y
                    dragging = false
                    longPressFired = false
                    scheduleLongPress { longPressFired = true; showMenu() }
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (!dragging && (Math.abs(dx) > touchSlop || Math.abs(dy) > touchSlop)) {
                        dragging = true
                        cancelLongPress()
                        hideMenu()
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
                    cancelLongPress()
                    if (longPressFired) {
                        // The press already did its work; this is its release.
                        longPressFired = false
                    } else if (menuView != null && !dragging) {
                        // A second tap on the bubble closes its own menu.
                        hideMenu()
                    } else if (dragging) {
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
                MotionEvent.ACTION_CANCEL -> {
                    cancelLongPress()
                    return true
                }
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
    /**
     * Tapping the bubble opens the panel and nothing else - never the main app
     * (the panel has its own task affinity for exactly that reason).
     *
     * The bubble no longer stops itself here: it steps aside for the panel and
     * comes back when the panel closes, so the reply flow can run twice in a
     * row (docs/FLOATING_OVERLAY.md §5.3).
     */
    private fun openPanel() {
        val intent = OverlayPanelActivity.createIntent(this)
        panelContext = OverlayBubbleController.peek()
        try {
            startActivity(intent)
        } catch (error: Exception) {
            // No activity to open (rare, but a crash here would look like a
            // broken bubble); keep the bubble so the user can try again.
            panelContext = null
            return
        }
        hideForPanel()
    }

    /** Invisible, not removed: the panel is drawn in front of this window. */
    private fun hideForPanel() {
        panelOpen = true
        hideMenu()
        stopIdleAnimation()
        bubbleView?.visibility = View.GONE
        // The auto-hide timer keeps running on purpose: if the panel never
        // reports back (process died, user swiped the task away) the bubble
        // still cleans itself up instead of lingering invisibly forever.
    }

    private fun onPanelClosed() {
        panelOpen = false
        val view = bubbleView
        if (view == null) {
            panelContext = null
            return
        }
        // The panel consumed the context; hand the same one back so the bubble
        // still means something and a second tap reopens the same message.
        if (OverlayBubbleController.peek() == null && panelContext != null) {
            OverlayBubbleController.hold(panelContext!!)
        }
        panelContext = null
        if (OverlayBubbleController.peek() == null) {
            removeBubble()
            stopSelf()
            return
        }
        view.visibility = View.VISIBLE
        startIdleAnimation()
        scheduleAutoHide()
    }

    private fun removeBubble() {
        hideMenu()
        cancelLongPress()
        val view = bubbleView
        val manager = windowManager
        bubbleView = null
        layoutParams = null
        badgeView = null
        iconView = null
        gripView = null
        collapsed = false
        stopIdleAnimation()
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

    /**
     * The panel tells the service when it is gone, which is the only moment the
     * bubble can safely come back.
     */
    private fun registerPanelReceiver() {
        val filter = IntentFilter(ACTION_PANEL_CLOSED)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == ACTION_PANEL_CLOSED) onPanelClosed()
            }
        }
        panelReceiver = receiver
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }
        } catch (error: Exception) {
            panelReceiver = null
        }
    }

    private fun unregisterPanelReceiver() {
        val receiver = panelReceiver ?: return
        panelReceiver = null
        try {
            unregisterReceiver(receiver)
        } catch (error: Exception) {
            // Already unregistered.
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

    private fun menuBackgroundColor(): Int = getColor(R.color.overlay_menu_background)

    private fun badgeColor(): Int = getColor(R.color.overlay_fallback_accent)

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        /** docs/FLOATING_OVERLAY.md §5.3: a bubble nobody uses goes away. */
        private const val AUTO_HIDE_MILLIS = 10 * 60 * 1000L

        /** Fixed id: one bubble notification, replaced rather than stacked. */
        const val OVERLAY_NOTIFICATION_ID = 4211
        const val CHANNEL_ID = "replymate_bubble"

        /** Long enough to be deliberate, short enough not to feel stuck. */
        private const val LONG_PRESS_MILLIS = 450L

        /** The menu closes itself if it is ignored. */
        private const val MENU_TIMEOUT_MILLIS = 6_000L

        /** App-private: the panel broadcasts this when it is destroyed. */
        const val ACTION_PANEL_CLOSED = "com.keshabstudios.replymate.action.PANEL_CLOSED"

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
