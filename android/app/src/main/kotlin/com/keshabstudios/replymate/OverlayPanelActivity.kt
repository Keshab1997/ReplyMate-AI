package com.keshabstudios.replymate

import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivityLaunchConfigs

/**
 * The translucent Flutter host for the reply panel.
 *
 * It exists for one reason: the panel has to float over the messaging app the
 * user is in, so this activity is transparent, never appears in Recents, and
 * cannot be started by anything else (`exported="false"`). Everything the user
 * sees is Dart - `OverlayPanelScreen` at [ROUTE_OVERLAY] - which means the
 * panel reuses the real reply flow instead of a Kotlin reimplementation
 * md §4.1).
 *
 * The pending message is read once through `consumeOverlayContext` and is never
 * written to disk or a log by this activity.
 *
 * It extends [ReplyMateFlutterActivity] rather than `FlutterActivity` on
 * purpose: that is where the platform channel lives, and without it this
 * activity's engine could not answer `consumeOverlayContext` at all.
 */
class OverlayPanelActivity : ReplyMateFlutterActivity() {

    override fun getInitialRoute(): String = ROUTE_OVERLAY

    /**
     * Transparent, not opaque: the conversation stays visible behind the
     * panel, and the window theme (`OverlayPanelTheme`) is translucent to
     * match. This is the Flutter-supported way to do it - no window hacks.
     */
    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode =
        FlutterActivityLaunchConfigs.BackgroundMode.transparent

    /**
     * A second notification can arrive while the panel is open. The panel
     * consumes its context once, so it cannot see a newer message by itself:
     * when one is pending, this activity hands over to a fresh panel that reads
     * it. With nothing pending it stays put - the user's current message should
     * not disappear because an unrelated notification arrived.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (OverlayBubbleController.peek() == null) return
        setIntent(intent)
        finish()
        try {
            startActivity(createIntent(this))
        } catch (error: Exception) {
            // No second panel can be opened; the message stays pending and the
            // next bubble tap picks it up.
        }
    }

    /**
     * Whatever the user did here, the bubble has to come back: it only stepped
     * aside so the panel could be read. The service re-shows it (and re-arms
     * the pending context) when this broadcast arrives.
     */
    override fun onDestroy() {
        try {
            sendBroadcast(
                Intent(OverlayBubbleService.ACTION_PANEL_CLOSED).setPackage(packageName),
            )
        } catch (error: Exception) {
            // The bubble's own auto-hide timer is the backstop.
        }
        super.onDestroy()
    }

    companion object {
        /** Must match `AppRoutes.overlay` in lib/app/app_routes.dart. */
        const val ROUTE_OVERLAY = "/overlay"

        fun createIntent(context: Context): Intent =
            Intent(context, OverlayPanelActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
            }
    }
}
