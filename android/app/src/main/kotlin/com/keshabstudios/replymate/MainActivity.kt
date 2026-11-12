package com.keshabstudios.replymate

/**
 * The main app entry point.
 *
 * Everything it used to do - the platform channel, the launch context, the
 * permission plumbing - now lives in [ReplyMateFlutterActivity], because the
 * reply panel is a second Flutter launch that needs exactly the same channel.
 * What is left here is what is genuinely MainActivity's own: the intent action
 * the fallback notification uses to ask for the pending message.
 */
class MainActivity : ReplyMateFlutterActivity() {

    companion object {
        /**
         * Tells MainActivity that the user tapped ReplyMate's fallback
         * notification, so the pending overlay context is consumed and the
         * composer opens prefilled instead of Home.
         *
         * The bubble itself does not use this any more - it launches
         * [OverlayPanelActivity] directly.md, Batch 2).
         */
        const val ACTION_OVERLAY_PANEL =
            "com.keshabstudios.replymate.action.OVERLAY_PANEL"
    }
}
