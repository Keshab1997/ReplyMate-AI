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
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
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
    private var rimView: View? = null
    private var highlightView: View? = null

    /** Drives idle and edge-settling motion; cancelled for direct manipulation. */
    private var bobAnimator: ValueAnimator? = null
    private var settleAnimator: ValueAnimator? = null
    private var lastBadgeCount = 0
    private var showMoodAfterExpand = false

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

    /** The "dismissed - undo" pill, while its few seconds are running. */
    private var undoPill: View? = null

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

    /**
     * Where the bubble sits *before* a drag, so an interrupted drag can put it
     * back. Only meaningful for the duration of one gesture.
     */
    private var gestureOriginX = 0
    private var gestureOriginY = 0

    /**
     * Set by the long-press menu's dismiss row and read once, after the menu
     * window is gone: a button inside a window that is being removed cannot
     * post a snackbar, so the service reports the undo window to the app and the
     * app does the drawing. Never carries message content.
     */
    private var pendingUndo: Map<String, Any?>? = null

    /** Notification key currently represented by the bubble. */
    private var shownKey: String? = null

    /**
     * The controller revision the bubble last reacted to. A second message from
     * the *same* chat keeps the same notification key, so the key alone cannot
     * tell us anything new happened.
     */
    private var shownRevision = -1L

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
        instance = this
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
            // A newer message updates the badge instead of stacking a second
            // bubble nobody asked for. "Newer" is the controller's revision, not
            // the notification key: a chat that posts twice keeps the same key,
            // and comparing keys alone made that second message arrive in
            // complete silence - no pop, no face, no badge. One message from one
            // chat is still one chat, so the badge stays at 1; what the revision
            // buys is the feedback that something just happened.
            val revision = OverlayBubbleController.revision()
            if (key != null && (key != shownKey || revision != shownRevision)) {
                shownKey = key
                shownRevision = revision
                // The badge is the real number of waiting chats, not a tap
                // counter: three chats pinging you must say three.
                messagesWhileShowing = OverlayBubbleController.size()
                // A message the user has not seen is worth interrupting for,
                // even if they had tucked the bubble away.
                if (collapsed) {
                    showMoodAfterExpand = true
                    expand()
                } else {
                    pulseOnce()
                    showMessageMood()
                }
                updateBadge(animate = true)
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
            shownRevision = OverlayBubbleController.revision()
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
        hideUndoPill()
        stopIdleAnimation()
        settleAnimator?.cancel()
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
        instance = null
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
            root.elevation = dp(10).toFloat()
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
        badge.typeface = android.graphics.Typeface.DEFAULT_BOLD
        badge.gravity = Gravity.CENTER
        badge.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(badgeColor())
            setStroke(dp(2), Color.WHITE)
        }
        badge.visibility = View.GONE
        // A count that changes silently is a count only sighted users have.
        badge.accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        val badgeSize = dp(22)
        root.addView(
            badge,
            FrameLayout.LayoutParams(badgeSize, badgeSize).apply {
                gravity = Gravity.TOP or Gravity.END
                topMargin = dp(1)
                rightMargin = dp(1)
            },
        )
        badgeView = badge
        iconView = icon

        // A separate rim stays crisp above the artwork instead of being painted
        // underneath a centre-cropped bitmap. The small highlight gives the
        // bubble a tactile glass edge without putting any content on it.
        val rim = View(this)
        rim.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.TRANSPARENT)
            setStroke(dp(1), Color.argb(205, 240, 248, 255))
        }
        rim.isClickable = false
        root.addView(rim, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        ))
        rimView = rim
        val highlight = View(this)
        highlight.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.argb(48, 255, 255, 255))
        }
        highlight.rotation = -28f
        highlight.isClickable = false
        root.addView(highlight, FrameLayout.LayoutParams(dp(20), dp(7)).apply {
            gravity = Gravity.TOP or Gravity.START
            leftMargin = dp(10)
            topMargin = dp(5)
        })
        highlightView = highlight

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

        // Accessibility first: a View with a touch listener and no click
        // handler is read aloud but cannot be *activated* by TalkBack, which
        // made the bubble an unopenable picture for anyone using a screen
        // reader. Clickable + performClick + a named long-press action is what
        // makes "Double-tap to activate" and "Actions available" both true.
        root.isClickable = true
        root.isFocusable = true
        root.setOnClickListener {
            if (collapsed) expand() else openPanel()
        }
        root.setOnLongClickListener {
            if (collapsed) {
                expand()
                true
            } else if (panelOpen) {
                false
            } else {
                // Haptic feedback is part of the gesture for sighted users; for
                // an accessibility activation it is just as useful.
                it.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                showMenu()
                true
            }
        }
        root.accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(
                host: View,
                info: android.view.accessibility.AccessibilityNodeInfo,
            ) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = "android.widget.Button"
                // The menu is the bubble's second door; a screen-reader user
                // should be able to reach it without discovering long-press.
                if (!collapsed && !panelOpen) {
                    // ACTION_LONG_CLICK is a plain action id, not an
                    // AccessibilityAction: it is the one TalkBack exposes as
                    // "Actions available", and the label above explains it.
                    info.addAction(
                        android.view.accessibility.AccessibilityNodeInfo.ACTION_LONG_CLICK,
                    )
                }
                if (collapsed) {
                    info.addAction(
                        android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction(
                            android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK,
                            getString(R.string.overlay_bubble_expand),
                        ),
                    )
                }
            }
        }
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
        if (!motionEnabled() || collapsed || panelOpen) {
            icon.setImageResource(R.drawable.overlay_bubble_mascot)
            return
        }
        val amplitude = dp(2).toFloat()
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1_800L
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            interpolator = DecelerateInterpolator()
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
        handler.removeCallbacks(moodRunnable)
        iconView?.let {
            it.translationY = 0f
            it.scaleY = 1f
            it.setImageResource(R.drawable.overlay_bubble_mascot)
        }
    }

    /** Swap only the eyes/face artwork: never squash the whole mascot. */
    private val blinkRunnable = object : Runnable {
        override fun run() {
            val icon = iconView
            if (icon != null && !collapsed && !panelOpen && motionEnabled()) {
                icon.setImageResource(R.drawable.overlay_bubble_mascot_blink)
                handler.postDelayed({
                    if (iconView === icon && !collapsed && !panelOpen) {
                        icon.setImageResource(R.drawable.overlay_bubble_mascot)
                    }
                }, 150L)
            }
            scheduleBlink()
        }
    }

    private val moodRunnable = Runnable {
        if (!collapsed && !panelOpen) {
            iconView?.setImageResource(R.drawable.overlay_bubble_mascot)
        }
    }

    private fun scheduleBlink() {
        handler.removeCallbacks(blinkRunnable)
        if (motionEnabled()) {
            handler.postDelayed(
                blinkRunnable,
                3_500L + (Math.random() * 3_000L).toLong(),
            )
        }
    }

    /** New-message delight, or an honest alert face for incomplete context. */
    private fun showMessageMood() {
        val icon = iconView ?: return
        handler.removeCallbacks(moodRunnable)
        val pending = OverlayBubbleController.peek()
        val needsAttention = pending?.let {
            it["mayBeRedacted"] == true || it["isTruncated"] == true ||
                it["isGroupSummary"] == true
        } == true
        icon.setImageResource(
            if (needsAttention) R.drawable.overlay_bubble_mascot_alert
            else R.drawable.overlay_bubble_mascot_happy,
        )
        handler.postDelayed(moodRunnable, if (needsAttention) 1_600L else 900L)
    }

    private fun motionEnabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ValueAnimator.areAnimatorsEnabled()
        } else {
            Settings.Global.getFloat(
                contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f,
            ) != 0f
        }
    }

    /** New message: one soft pop plus a tap of haptic feedback. */
    private fun pulseOnce() {
        val view = bubbleView ?: return
        if (collapsed || panelOpen) return
        view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        if (!motionEnabled()) return
        view.animate()
            .scaleX(1.08f)
            .scaleY(1.1f)
            .setDuration(160L)
            .withEndAction {
                view.animate().scaleX(1f).scaleY(1f).setDuration(200L).start()
            }
            .start()
    }

    private fun updateBadge(animate: Boolean = false) {
        val badge = badgeView ?: return
        val count = messagesWhileShowing
        badge.text = if (count > 9) "9+" else count.toString()
        badge.visibility = if (count > 1) View.VISIBLE else View.GONE
        if (animate && count > 1 && count != lastBadgeCount && motionEnabled()) {
            badge.scaleX = 0.65f
            badge.scaleY = 0.65f
            badge.animate()
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(280L)
                .setInterpolator(OvershootInterpolator(1.4f))
                .start()
        }
        lastBadgeCount = count
    }

    /**
     * The user's hide-after choice in milliseconds, or [NO_TIMER] when they chose
     * "Never". Read from native prefs on every schedule: the settings
     * screen can change it while this service is alive, and a bubble that kept
     * a stale timer would be a setting that only works after a restart.
     */
    private fun autoHideMillis(): Long {
        val minutes = prefs().getInt(KEY_BUBBLE_AUTO_HIDE_MINUTES, DEFAULT_AUTO_HIDE_MINUTES)
        if (minutes == AUTO_HIDE_NEVER) return NO_TIMER
        val known = minutes == 5 || minutes == 10 || minutes == 30
        return (if (known) minutes else DEFAULT_AUTO_HIDE_MINUTES) * 60_000L
    }

    private fun scheduleAutoHide() {
        handler.removeCallbacks(autoHide)
        val millis = autoHideMillis()
        // 0 is the user saying "never tidy the bubble away for me". Leaving the
        // timer unscheduled is the honest reading of that; autoHide still runs
        // when the message is withdrawn or the switch is turned off.
        if (millis == NO_TIMER) return
        handler.postDelayed(autoHide, millis)
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
            orientation = GradientDrawable.Orientation.TL_BR
            colors = intArrayOf(bubbleColor(), Color.rgb(17, 79, 208))
            setStroke(dp(1), Color.argb(190, 235, 246, 255))
            if (collapsed) {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = tabWidth / 2f
            } else {
                shape = GradientDrawable.OVAL
            }
        }
        iconView?.visibility = if (collapsed) View.GONE else View.VISIBLE
        rimView?.visibility = if (collapsed) View.GONE else View.VISIBLE
        highlightView?.visibility = if (collapsed) View.GONE else View.VISIBLE
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
        applyBubbleAppearance(view, collapsed = true)
        animateWindowLayout(
            view,
            params,
            targetX = if (toRight) metrics.widthPixels - tabWidth else 0,
            targetWidth = tabWidth,
            targetHeight = size,
        )
    }

    /** Brings a tucked bubble back to full size on the edge it was hiding on. */
    private fun expand() {
        val params = layoutParams ?: return
        val view = bubbleView ?: return
        val size = resources.getDimensionPixelSize(R.dimen.overlay_bubble_size)
        val metrics = resources.displayMetrics
        val onRight = params.x > metrics.widthPixels / 2
        collapsed = false
        applyBubbleAppearance(view, collapsed = false)
        iconView?.alpha = 0f
        iconView?.animate()?.alpha(1f)?.setDuration(if (motionEnabled()) 180L else 0L)?.start()
        animateWindowLayout(
            view,
            params,
            targetX = if (onRight) metrics.widthPixels - size else 0,
            targetWidth = size,
            targetHeight = size,
        ) {
            updateBadge()
            startIdleAnimation()
            if (showMoodAfterExpand) {
                showMoodAfterExpand = false
                showMessageMood()
            }
            rememberPosition(params)
        }
    }

    /** A small, damped spring settles the real overlay window, not a proxy. */
    private fun animateWindowLayout(
        view: View,
        params: WindowManager.LayoutParams,
        targetX: Int,
        targetWidth: Int,
        targetHeight: Int,
        onEnd: () -> Unit = {},
    ) {
        settleAnimator?.cancel()
        if (!motionEnabled()) {
            params.x = targetX
            params.width = targetWidth
            params.height = targetHeight
            try {
                windowManager?.updateViewLayout(view, params)
            } catch (error: Exception) {
                collapsed = false
            }
            onEnd()
            return
        }
        val fromX = params.x
        val fromWidth = params.width
        val fromHeight = params.height
        settleAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 340L
            interpolator = OvershootInterpolator(0.7f)
            addUpdateListener { animation ->
                val fraction = animation.animatedValue as Float
                params.x = (fromX + (targetX - fromX) * fraction).toInt()
                params.width = (fromWidth + (targetWidth - fromWidth) * fraction).toInt()
                params.height = (fromHeight + (targetHeight - fromHeight) * fraction).toInt()
                try {
                    windowManager?.updateViewLayout(view, params)
                } catch (error: Exception) {
                    cancel()
                }
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                private var cancelled = false

                override fun onAnimationCancel(animation: android.animation.Animator) {
                    cancelled = true
                }

                override fun onAnimationEnd(animation: android.animation.Animator) {
                    settleAnimator = null
                    if (!cancelled) onEnd()
                }
            })
            start()
        }
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
                if (!collapsed) startIdleAnimation()
                // A tab dragged into the middle of the screen would just look
                // broken, so letting go of it restores the full bubble.
                if (collapsed) expand()
            }
        }
    }

    /**
     * The area the bubble is allowed to occupy.
     *
     * `displayMetrics.heightPixels` is the whole panel, which on a device with a
     * navigation bar, a status bar or a display cutout is not where the bubble
     * can live: a bubble parked at the bottom used to sit under the nav bar, and
     * one at the top under the notch. Since API 30 the window metrics answer
     * this properly; before that, the safe insets are subtracted by hand.
     */
    private fun usableBounds(): android.graphics.Rect {
        val area = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            windowManager?.currentWindowMetrics?.bounds
                ?: android.graphics.Rect(
                    0,
                    0,
                    resources.displayMetrics.widthPixels,
                    resources.displayMetrics.heightPixels,
                )
        } else {
            @Suppress("DEPRECATION")
            val legacy = android.graphics.Rect(
                0,
                0,
                resources.displayMetrics.widthPixels,
                resources.displayMetrics.heightPixels,
            )
            legacy
        }
        val insets = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            windowManager?.currentWindowMetrics?.windowInsets
                ?.getInsetsIgnoringVisibility(
                    android.view.WindowInsets.Type.systemBars() or
                        android.view.WindowInsets.Type.displayCutout(),
                )
        } else {
            null
        }
        if (insets != null) {
            area.inset(insets.left, maxOf(insets.top, dp(8)), insets.right, insets.bottom)
        }
        return area
    }

    /**
     * Keeps a window position inside [usableBounds]. Applied to the remembered
     * position and, after a configuration change, to the live window: a bubble
     * at the bottom edge in portrait is off-screen once the device rotates, and
     * the user reads that as a crash.
     */
    private fun clampToBounds(params: WindowManager.LayoutParams) {
        val area = usableBounds()
        val maxX = maxOf(area.left, area.right - params.width)
        val maxY = maxOf(area.top, area.bottom - params.height)
        params.x = params.x.coerceIn(area.left, maxX)
        params.y = params.y.coerceIn(area.top, maxY)
    }

    /**
     * A rotation or a window resize moves the goalposts, not just the pixels.
     * The bubble re-clamps, keeps its edge, and drops the cached menu (which is
     * positioned in the old orientation) instead of leaving it floating in the
     * wrong place.
     */
    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        hideMenu()
        val params = layoutParams ?: return
        val view = bubbleView ?: return
        if (collapsed) {
            // Recompute the tab's edge from the new width rather than trusting
            // the old x, which now points somewhere in the middle of the screen.
            val onRight = params.x + params.width / 2 > usableBounds().centerX()
            params.x = if (onRight) {
                usableBounds().right - params.width
            } else {
                usableBounds().left
            }
        } else {
            clampToBounds(params)
        }
        try {
            windowManager?.updateViewLayout(view, params)
        } catch (error: Exception) {
            // The window went away with the configuration change.
        }
        rememberPosition(params)
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
            )
            y = defaults.getInt(
                KEY_BUBBLE_Y,
                resources.getDimensionPixelSize(R.dimen.overlay_bubble_default_y),
            )
        }.also { clampToBounds(it) }
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
        card.setPadding(0, dp(6), 0, dp(6))
        card.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(18).toFloat()
            setColor(menuBackgroundColor())
            setStroke(dp(1), Color.argb(32, 255, 255, 255))
        }
        card.elevation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            dp(14).toFloat()
        } else {
            0f
        }
        // ACTION_OUTSIDE arrives because the window asked to watch for it. It
        // carries coordinates outside our own view, so no row can have been
        // touched: closing is the only honest response.
        card.setOnTouchListener { _, event ->
            if (event.actionMasked == MotionEvent.ACTION_OUTSIDE) {
                hideMenu()
                true
            } else {
                false
            }
        }
        val actions = listOf(
            Triple(R.string.overlay_bubble_menu_reply, R.drawable.overlay_ic_reply) { openPanel() },
            Triple(R.string.overlay_bubble_menu_hide, R.drawable.overlay_ic_hide) {
                collapse(toRight = anchor.x > resources.displayMetrics.widthPixels / 2)
            },
            Triple(R.string.overlay_bubble_menu_dismiss, R.drawable.overlay_ic_dismiss) {
                // The same path as a swipe, so the menu's dismiss also offers
                // the five-second undo instead of being final.
                dismissBySwipe()
            },
        )
        actions.forEachIndexed { index, item ->
            if (index > 0) {
                val divider = View(this)
                divider.setBackgroundColor(Color.argb(20, 255, 255, 255))
                card.addView(divider, LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    dp(1),
                ).apply { leftMargin = dp(48); rightMargin = dp(12) })
            }
            card.addView(menuRow(item.first, item.second, item.third))
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val width = dp(204)
        val estimatedHeight = dp(3 * 48 + 14)
        val metrics = resources.displayMetrics
        val params = WindowManager.LayoutParams(
            width,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            // NOT_FOCUSABLE keeps the app underneath usable, which is the point
            // of a bubble. WATCH_OUTSIDE_TOUCH is what makes the *first* tap
            // elsewhere close the menu: without it that tap went straight to the
            // other app and the menu sat there until its six-second timeout,
            // which reads as a stuck menu.
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = if (anchor.x + anchor.width + width + dp(10) <= metrics.widthPixels) {
                anchor.x + anchor.width + dp(10)
            } else {
                (anchor.x - width - dp(10)).coerceAtLeast(dp(8))
            }
            y = anchor.y.coerceIn(
                dp(8),
                maxOf(dp(8), metrics.heightPixels - estimatedHeight - dp(8)),
            )
        }
        // The menu is a second window with no activity behind it, so nothing
        // announces that it appeared. A polite live region on the card, plus a
        // heading for the first row, is what tells a screen-reader user the
        // menu is there and what is in it.
        card.accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        card.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        try {
            manager.addView(card, params)
            menuView = card
            // Move accessibility focus onto the menu instead of leaving it on a
            // bubble that is now partly covered.
            card.announceForAccessibility(getString(R.string.overlay_bubble_menu_description))
            if (motionEnabled()) {
                card.alpha = 0f
                card.scaleX = 0.96f
                card.scaleY = 0.96f
                card.pivotX = if (params.x > anchor.x) 0f else width.toFloat()
                card.animate()
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(180L)
                    .setInterpolator(DecelerateInterpolator())
                    .start()
            }
            menuTimeout?.let { handler.removeCallbacks(it) }
            val timeout = Runnable { hideMenu() }
            menuTimeout = timeout
            handler.postDelayed(timeout, MENU_TIMEOUT_MILLIS)
        } catch (error: Exception) {
            // A refused menu window must never take the bubble down with it.
            menuView = null
        }
    }

    private fun menuRow(labelRes: Int, iconRes: Int, action: () -> Unit): View {
        val row = TextView(this)
        row.text = getString(labelRes)
        // A TextView with a click listener is fine for touch and invisible as a
        // control to TalkBack; the role, not the class, is what is missing.
        row.isClickable = true
        row.isFocusable = true
        row.accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(
                host: View,
                info: android.view.accessibility.AccessibilityNodeInfo,
            ) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = "android.widget.Button"
            }
        }
        row.setTextColor(Color.rgb(238, 244, 255))
        row.textSize = 14f
        row.gravity = Gravity.CENTER_VERTICAL
        row.setPadding(dp(14), 0, dp(14), 0)
        row.compoundDrawablePadding = dp(12)
        row.setCompoundDrawablesRelativeWithIntrinsicBounds(iconRes, 0, 0, 0)
        row.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(48),
        )
        row.setOnClickListener {
            row.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
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

        /**
         * Where and when this gesture started, kept for [isFlick]: by ACTION_UP
         * the touch slop has already let a slow drag through, and a flick is the
         * opposite - fast and short.
         */
        private var downRawXForGesture = 0f
        private var downRawYForGesture = 0f
        private var downTimeForGesture = 0L

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val params = layoutParams ?: return false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    downRawXForGesture = event.rawX
                    downRawYForGesture = event.rawY
                    downTimeForGesture = event.eventTime
                    startX = params.x
                    startY = params.y
                    gestureOriginX = params.x
                    gestureOriginY = params.y
                    dragging = false
                    longPressFired = false
                    settleAnimator?.cancel()
                    if (motionEnabled()) {
                        view.animate().scaleX(0.96f).scaleY(0.96f).setDuration(90L).start()
                    }
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
                        stopIdleAnimation()
                        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        if (motionEnabled()) {
                            view.animate().scaleX(1.06f).scaleY(1.06f).setDuration(110L).start()
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                view.elevation = dp(14).toFloat()
                            }
                        }
                    }
                    if (dragging) {
                        // Clamped while the finger is still down, not only on
                        // release: dragging past the edge used to park the
                        // window off-screen entirely, and a bubble the user
                        // cannot see or touch is indistinguishable from one that
                        // crashed. The margin keeps the whole disc reachable.
                        val metrics = resources.displayMetrics
                        val maxX = maxOf(0, metrics.widthPixels - params.width)
                        val maxY = maxOf(0, metrics.heightPixels - params.height)
                        params.x = (startX + dx.toInt()).coerceIn(0, maxX)
                        params.y = (startY + dy.toInt()).coerceIn(0, maxY)
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
                    releaseBubble(view)
                    // A quick flick counts as "get rid of this", the gesture
                    // people already try on anything that floats. It is checked
                    // before the tap branch because a flick also ends in UP.
                    if (!longPressFired && !collapsed && isFlick(event)) {
                        dismissBySwipe()
                        return true
                    }
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
                    releaseBubble(view)
                    // The window going away mid-drag must not leave the bubble
                    // half-way to nowhere: put it back where the gesture
                    // started, which is the last position the user chose.
                    if (dragging) {
                        params.x = gestureOriginX
                        params.y = gestureOriginY
                        try {
                            windowManager?.updateViewLayout(view, params)
                        } catch (error: Exception) {
                            // Window is gone; the next show positions it again.
                        }
                    }
                    if (!collapsed && !panelOpen) startIdleAnimation()
                    return true
                }
            }
            return false
        }
    }

    /**
     * A fast, short flick: far enough to be deliberate, finished quickly enough
     * that nobody who was only moving the bubble can trip it. A slow drag is a
     * move, which is the gesture the bubble was built around.
     */
    private fun isFlick(event: MotionEvent): Boolean {
        val distance = Math.hypot(
            (event.rawX - downRawXForGesture).toDouble(),
            (event.rawY - downRawYForGesture).toDouble(),
        )
        val duration = event.eventTime - downTimeForGesture
        return distance > dp(FLICK_DISTANCE_DP) && duration < FLICK_DURATION_MILLIS
    }

    /**
     * Swipe-to-dismiss, with an undo window the long-press menu never had.
     *
     * The bubble and its pending message both go - that is what dismissing
     * means (docs/FLOATING_OVERLAY.md §5.3) - but the context is kept in a small
     * native pill for a few seconds instead of being destroyed. A snackbar in the
     * app would be the obvious place for it and the wrong one: a swipe happens
     * over *another* app, where no Flutter engine is alive and nothing of ours is
     * on screen. So the pill is drawn by this service, like everything else here.
     */
    private fun dismissBySwipe() {
        val snapshot = OverlayBubbleController.peekAll()
        bubbleView?.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        val view = bubbleView
        val manager = windowManager
        val anchorX = layoutParams?.x ?: 0
        val anchorY = layoutParams?.y ?: 0
        val finish = {
            removeBubble()
            if (snapshot.isEmpty()) {
                stopSelf()
            } else {
                showUndoPill(snapshot, anchorX, anchorY)
            }
        }
        if (view != null && manager != null && motionEnabled()) {
            view.animate().alpha(0f).scaleX(0.7f).scaleY(0.7f)
                .setDuration(140L)
                .withEndAction { finish() }
                .start()
        } else {
            finish()
        }
    }

    /**
     * "Dismissed - Undo", in the bubble's own place, for [UNDO_SECONDS].
     *
     * It carries no message text and no sender: the pill says what happened, not
     * what it was about, so a glance at the screen over someone's shoulder still
     * learns nothing. Tapping it puts the contexts back and redraws the bubble;
     * ignoring it lets the timer drop them.
     */
    private fun showUndoPill(
        snapshot: List<Map<String, Any?>>,
        anchorX: Int,
        anchorY: Int,
    ) {
        val manager = windowManager ?: return
        val pill = TextView(this)
        pill.text = getString(R.string.overlay_bubble_undo)
        pill.setTextColor(Color.WHITE)
        pill.textSize = 14f
        pill.gravity = Gravity.CENTER
        pill.setPadding(dp(16), dp(10), dp(16), dp(10))
        pill.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(22).toFloat()
            setColor(menuBackgroundColor())
            setStroke(dp(1), Color.argb(48, 255, 255, 255))
        }
        // Same accessibility contract as the bubble: a real button, not a
        // picture with a touch listener.
        pill.isClickable = true
        pill.isFocusable = true
        pill.accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(
                host: View,
                info: android.view.accessibility.AccessibilityNodeInfo,
            ) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = "android.widget.Button"
            }
        }
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val area = usableBounds()
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = anchorX.coerceIn(area.left, maxOf(area.left, area.right - dp(140)))
            y = anchorY.coerceIn(area.top, maxOf(area.top, area.bottom - dp(48)))
        }
        pill.setOnClickListener {
            hideUndoPill()
            // Oldest first, so the newest message ends up back on top exactly as
            // it was before the swipe.
            snapshot.asReversed().forEach { OverlayBubbleController.hold(it) }
            show()
        }
        try {
            manager.addView(pill, params)
            undoPill = pill
            pill.announceForAccessibility(getString(R.string.overlay_bubble_dismissed))
            handler.postDelayed(removeUndoPill, UNDO_SECONDS * 1_000L)
        } catch (error: Exception) {
            // A refused pill window costs the undo, never the dismissal.
            undoPill = null
            stopSelf()
        }
    }

    private val removeUndoPill = Runnable { hideUndoPill() }

    private fun hideUndoPill() {
        handler.removeCallbacks(removeUndoPill)
        val view = undoPill
        undoPill = null
        if (view != null) {
            try {
                windowManager?.removeView(view)
            } catch (error: Exception) {
                // Already gone.
            }
        }
    }

    private fun releaseBubble(view: View) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            view.elevation = dp(10).toFloat()
        }
        if (motionEnabled()) {
            view.animate()
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(260L)
                .setInterpolator(OvershootInterpolator(1.1f))
                .start()
        } else {
            view.scaleX = 1f
            view.scaleY = 1f
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

    /**
     * Sends the bubble to the screen edge without losing it. Used when the
     * message's notification is withdrawn - which is what messaging apps do the
     * moment you open the conversation - so the bubble steps aside instead of
     * vanishing. Tapping the tab brings it straight back.
     */
    private fun tuck() {
        val params = layoutParams ?: return
        if (bubbleView == null || panelOpen) return
        if (collapsed) return
        collapse(toRight = params.x > resources.displayMetrics.widthPixels / 2)
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
        rimView = null
        highlightView = null
        settleAnimator?.cancel()
        settleAnimator = null
        lastBadgeCount = 0
        showMoodAfterExpand = false
        collapsed = false
        stopIdleAnimation()
        shownKey = null
        shownRevision = -1L
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
        /**
         * docs/FLOATING_OVERLAY.md §5.4: a bubble nobody uses goes away. The
         * default is ten minutes; the user can choose 5, 10, 30 or never.
         */
        private const val DEFAULT_AUTO_HIDE_MINUTES = 10

        /** The documented "never hide yourself" choice, in minutes. */
        private const val AUTO_HIDE_NEVER = 0

        /** Sentinel from autoHideMillis(): the user asked for no timer at all. */
        private const val NO_TIMER = -1L

        /** Fixed id: one bubble notification, replaced rather than stacked. */
        const val OVERLAY_NOTIFICATION_ID = 4211
        const val CHANNEL_ID = "replymate_bubble"

        /** Long enough to be deliberate, short enough not to feel stuck. */
        private const val LONG_PRESS_MILLIS = 450L

        /** The menu closes itself if it is ignored. */
        private const val MENU_TIMEOUT_MILLIS = 6_000L

        /** A flick: at least this far, in this little time. Otherwise it is a drag. */
        private const val FLICK_DISTANCE_DP = 72
        private const val FLICK_DURATION_MILLIS = 260L

        /** How long the app offers to bring a dismissed message back. */
        private const val UNDO_SECONDS = 5

        /** App-private: the panel broadcasts this when it is destroyed. */
        const val ACTION_PANEL_CLOSED = "com.keshabstudios.replymate.action.PANEL_CLOSED"

        @Volatile
        private var instance: OverlayBubbleService? = null

        /**
         * Tucks the live bubble against the nearest edge. A no-op when the
         * service is already gone - in that case the pending message is cleared
         * too, because a message with no bubble and no notification would
         * resurface later as a stale panel.
         */
        fun tuckAway(context: Context) {
            val service = instance
            if (service == null) {
                OverlayBubbleController.clear()
                return
            }
            service.handler.post { service.tuck() }
        }

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

        /** The user's hide-after choice, in minutes; 0 means never. */
        private const val KEY_BUBBLE_AUTO_HIDE_MINUTES = "bubble_auto_hide_minutes"

        /**
         * Records the user's hide-after choice natively, where the service can
         * read it with no Flutter engine alive - the same contract as the
         * bubble switch itself. A live bubble picks the new value up on its next
         * schedule, so the setting takes effect without waiting for a restart.
         */
        fun setAutoHideMinutesByUser(context: Context, minutes: Int) {
            val stored = when (minutes) {
                AUTO_HIDE_NEVER, 5, 10, 30 -> minutes
                else -> DEFAULT_AUTO_HIDE_MINUTES
            }
            try {
                context.getSharedPreferences(ReplyMateNotificationListener.PREFS_NAME, MODE_PRIVATE)
                    .edit()
                    .putInt(KEY_BUBBLE_AUTO_HIDE_MINUTES, stored)
                    .apply()
            } catch (error: Exception) {
                // Losing a preference is not worth a crash.
            }
            instance?.handler?.post {
                instance?.scheduleAutoHide()
            }
        }
    }
}
