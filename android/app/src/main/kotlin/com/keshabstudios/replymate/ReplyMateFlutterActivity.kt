package com.keshabstudios.replymate

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The Flutter host that owns the single platform channel.
 *
 * **Both** of our Flutter activities extend this, and that is the whole point:
 * the reply panel is a *separate Flutter launch* (`OverlayPanelActivity`) with
 * its own engine, so a channel wired only into `MainActivity` left the panel
 * with no channel at all - `consumeOverlayContext` answered
 * `MissingPluginException`, the panel fell back to "Nothing to reply to", and
 * tapping the bubble looked like a broken feature. One host class, one
 * contract (docs/PLATFORM_CHANNELS.md), no drift between the two activities.
 */
abstract class ReplyMateFlutterActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    /**
     * Text handed to us by another app (PROCESS_TEXT selection action or the
     * share sheet). Consumed once by Flutter via `consumeLaunchContext`.
     */
    private var launchContext: Map<String, Any?>? = null

    /** Set while the Android 13+ notification-permission dialog is open. */
    private var pendingNotificationPermission: MethodChannel.Result? = null

    /**
     * Identity of the native -> Dart sink this host installs, so tearing one
     * activity down cannot clear a sink another live activity owns.
     */
    private val eventForwarder: (Map<String, Any?>) -> Unit = { event ->
        runOnUiThread { channel?.invokeMethod("onEvent", event) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isListenerEnabled" -> result.success(isListenerEnabled())
                "openListenerSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "candidateApps" -> result.success(candidateApps())
                "setAllowedPackages" -> {
                    setAllowedPackages(call.argument<List<String>>("packages") ?: emptyList())
                    result.success(null)
                }
                "sendQuickReply" -> {
                    val text = call.argument<String>("text") ?: ""
                    val key = call.argument<String>("key")
                    result.success(
                        ReplyMateNotificationListener.instance?.sendQuickReply(text, key) == true,
                    )
                }
                "shareText" -> {
                    val text = call.argument<String>("text")?.trim().orEmpty()
                    if (text.isEmpty()) {
                        result.success(false)
                    } else {
                        try {
                            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                            }
                            startActivity(Intent.createChooser(sendIntent, "Share reply"))
                            result.success(true)
                        } catch (error: Exception) {
                            result.success(false)
                        }
                    }
                }
                "clearRetainedContext" -> {
                    ReplyMateNotificationListener.instance?.clearRetainedReplyAction()
                    result.success(null)
                }
                "consumeLaunchContext" -> {
                    result.success(launchContext)
                    launchContext = null
                }
                "isOverlayEnabled" -> result.success(Settings.canDrawOverlays(this))
                "openOverlaySettings" -> {
                    // Grants nothing by itself: Android keeps the decision.
                    try {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                    } catch (error: Exception) {
                        // Some OEMs hide the screen; the permission card then
                        // keeps saying "not granted", which is the truth.
                    }
                    result.success(null)
                }
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "setBubbleEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") == true
                    setBubbleEnabled(enabled)
                    result.success(null)
                }
                "screenReadingStatus" ->
                    result.success(ReplyMateScreenReaderService.report(this))
                "isScreenReadingAvailable" ->
                    result.success(isScreenReadingAvailable())
                "openAccessibilitySettings" -> {
                    // Grants nothing by itself: Android keeps the decision.
                    try {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    } catch (error: Exception) {
                        // Some OEMs hide the screen; the switch then keeps
                        // saying "not granted", which is the truth.
                    }
                    result.success(null)
                }
                "setScreenReadingEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") == true
                    getSharedPreferences(
                        ReplyMateNotificationListener.PREFS_NAME,
                        MODE_PRIVATE,
                    ).edit()
                        .putBoolean(
                            ReplyMateScreenReaderService.KEY_SCREEN_READING_ENABLED,
                            enabled,
                        )
                        .apply()
                    result.success(null)
                }
                "consumeOverlayContext" -> {
                    // One-shot: the pending map is cleared as it is handed out,
                    // so the panel can never read the same message twice.
                    result.success(OverlayBubbleController.consume())
                }
                "closeOverlayPanel" -> {
                    // Only the panel activity can close itself this way; from
                    // anywhere else the call is a no-op, not a crash.
                    if (this is OverlayPanelActivity) finish()
                    result.success(null)
                }
                "peekOverlayContexts" -> {
                    // Read-only: the panel's chat switcher needs every pending
                    // message, newest first, without consuming any of them.
                    result.success(OverlayBubbleController.peekAll())
                }
                else -> result.notImplemented()
            }
        }
        // Native -> Dart events. Forwarded on the UI thread; dropped when the
        // engine is gone (see ReplyMateNotificationListener.eventSink docs).
        ReplyMateNotificationListener.eventSink = eventForwarder
        captureLaunchContext(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureLaunchContext(intent)
    }

    /**
     * Starts the bubble service while the app is visible. Android 12+ forbids
     * starting a foreground service from the background, so this is the one
     * moment the service may be started; from then on the listener only
     * updates it (docs/FLOATING_OVERLAY.md §7).
     */
    override fun onStart() {
        super.onStart()
        if (OverlayBubbleService.isEnabledByUser(this) && Settings.canDrawOverlays(this)) {
            OverlayBubbleService.start(this)
        }
    }

    override fun onDestroy() {
        if (ReplyMateNotificationListener.eventSink === eventForwarder) {
            ReplyMateNotificationListener.eventSink = null
        }
        channel = null
        super.onDestroy()
    }

    /**
     * Android 13+ runtime notification permission. The answer is delivered from
     * [onRequestPermissionsResult], so the Dart side gets the real grant rather
     * than a guess.
     */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingNotificationPermission != null) {
            // One dialog at a time: the earlier caller gets the same answer.
            pendingNotificationPermission?.success(false)
        }
        pendingNotificationPermission = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_POST_NOTIFICATIONS) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingNotificationPermission?.success(granted)
        pendingNotificationPermission = null
    }

    /**
     * The user's bubble switch. Persisted natively because the listener reads it
     * with no Flutter engine alive; the service is started or stopped to match.
     */
    private fun setBubbleEnabled(enabled: Boolean) {
        OverlayBubbleService.setEnabledByUser(this, enabled)
        if (enabled && Settings.canDrawOverlays(this)) {
            OverlayBubbleService.start(this)
        } else if (!enabled) {
            OverlayBubbleController.clear()
            OverlayBubbleService.stop(this)
        }
    }

    /**
     * Whether Android has actually granted accessibility access to our screen
     * reader - the only way it can run at all.
     *
     * Read from the system setting rather than remembered, because the grant
     * happens on a screen Android owns: the user can turn it off there without
     * this app ever being told. This is also how an Android 16+ device with
     * Advanced Protection Mode shows up - the grant simply is not there, and
     * the UI says so instead of blaming the reader (docs/SCREEN_READING.md).
     */
    private fun isScreenReadingAvailable(): Boolean {
        val expected =
            ComponentName(this, ReplyMateScreenReaderService::class.java).flattenToString()
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
    }

    /**
     * Records text arriving through the two user-initiated entry points:
     * the text-selection action (PROCESS_TEXT) and the share sheet (SEND).
     * Anything else (a plain launch) leaves the context null.
     */
    private fun captureLaunchContext(intent: Intent?) {
        val received = intent ?: return
        when (received.action) {
            Intent.ACTION_PROCESS_TEXT -> {
                val text = received.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
                if (!text.isNullOrEmpty()) {
                    launchContext = mapOf("source" to "process_text", "text" to text)
                }
            }
            Intent.ACTION_SEND -> {
                val text = received.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                if (!text.isNullOrEmpty()) {
                    launchContext = mapOf("source" to "share", "text" to text)
                }
            }
        }
    }

    private fun isListenerEnabled(): Boolean {
        val enabled =
            Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                ?: return false
        val component = ComponentName(this, ReplyMateNotificationListener::class.java)
        val flat = component.flattenToString()
        return enabled.split(':').any { it == flat }
    }

    /**
     * Messaging apps ReplyMate knows how to work with. Only installed apps are
     * offered: the app must never claim support for something it cannot see
     * (docs/SCREEN_SPECIFICATIONS.md, screen 5).
     */
    private fun candidateApps(): List<Map<String, Any?>> {
        return CANDIDATE_PACKAGES.mapNotNull { packageName ->
            val label = try {
                packageManager.getApplicationLabel(
                    packageManager.getApplicationInfo(packageName, 0),
                ).toString()
            } catch (e: Exception) {
                null // not installed, or hidden by package-visibility rules
            }
            if (label == null) {
                null
            } else {
                mapOf<String, Any?>("packageName" to packageName, "label" to label)
            }
        }
    }

    private fun setAllowedPackages(packages: List<String>) {
        getSharedPreferences(ReplyMateNotificationListener.PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putStringSet(ReplyMateNotificationListener.KEY_ALLOWED_PACKAGES, packages.toSet())
            .apply()
    }

    private companion object {
        const val CHANNEL = "com.keshabstudios.replymate/notifications"
        const val REQUEST_POST_NOTIFICATIONS = 4311

        val CANDIDATE_PACKAGES = listOf(
            "com.whatsapp",
            "org.telegram.messenger",
            "com.facebook.orca",
            "org.thoughtcrime.securesms",
            "com.google.android.apps.messaging",
            "com.android.mms",
        )
    }
}
