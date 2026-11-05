package com.keshabstudios.replymate

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the single platform channel between Flutter and the native layer.
 * The full contract (methods, events, launch contexts) is documented in
 * docs/PLATFORM_CHANNELS.md.
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    /**
     * Text handed to us by another app (PROCESS_TEXT selection action or the
     * share sheet). Consumed once by Flutter via `consumeLaunchContext`.
     */
    private var launchContext: Map<String, Any?>? = null

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
                    result.success(
                        ReplyMateNotificationListener.instance?.sendQuickReply(text) == true,
                    )
                }
                "consumeLaunchContext" -> {
                    result.success(launchContext)
                    launchContext = null
                }
                else -> result.notImplemented()
            }
        }
        // Native -> Dart events. Forwarded on the UI thread; dropped when the
        // engine is gone (see ReplyMateNotificationListener.eventSink docs).
        ReplyMateNotificationListener.eventSink = { event ->
            runOnUiThread { channel?.invokeMethod("onEvent", event) }
        }
        captureLaunchContext(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureLaunchContext(intent)
    }

    override fun onDestroy() {
        ReplyMateNotificationListener.eventSink = null
        channel = null
        super.onDestroy()
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
