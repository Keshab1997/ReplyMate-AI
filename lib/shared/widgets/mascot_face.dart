import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// What the helper is doing right now. The face is the same artwork in every
/// state - the mood only changes how it holds itself and what light sits behind
/// it, so one PNG carries the whole personality and the APK stays small.
enum MascotMood {
  /// Resting: a slow bob and the occasional blink.
  idle,

  /// Reading a message the user just captured or pasted.
  listening,

  /// A request is in flight.
  thinking,

  /// Replies have arrived.
  happy,

  /// Something the user should look at (permission missing, guest mode).
  alert,
}

/// The ReplyMate face.
///
/// All motion is **finite on purpose**. An infinite ticker would keep
/// `pumpAndSettle` from ever settling (and would keep the GPU awake on a static
/// screen); the bubble - the thing the user actually watches over another app -
/// is where the continuous motion lives. Blinks are driven by the bob
/// controller rather than a `Timer`, so nothing is left pending when a screen
/// is disposed mid-test.
class MascotFace extends StatefulWidget {
  const MascotFace({
    this.size = 96,
    this.mood = MascotMood.idle,
    this.glow = true,
    this.animate = true,
    super.key,
  });

  final double size;
  final MascotMood mood;

  /// The soft radial halo behind the disc.
  final bool glow;

  /// Off for tests and for the small headers where motion would be noise.
  final bool animate;

  @override
  State<MascotFace> createState() => _MascotFaceState();
}

class _MascotFaceState extends State<MascotFace> with TickerProviderStateMixin {
  /// 12 round trips (~18 s) of life after the face appears: enough to feel
  /// animated, short enough to stay out of the way - and finite, so a widget
  /// test settles.
  static const int _cycles = 12;

  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  int _blinks = 0;
  bool _blinking = false;

  @override
  void initState() {
    super.initState();
    _bob.addListener(_maybeBlink);
    if (widget.animate) _start();
  }

  void _start() {
    _bob.repeat(reverse: true, count: _cycles);
  }

  /// One blink roughly every third bob, so it never looks like a metronome.
  void _maybeBlink() {
    if (!widget.animate || _blinking) return;
    if (_bob.value < 0.98) return;
    _blinking = true;
    _blinks += 1;
    if (_blinks % 3 != 1) {
      _blinking = false;
      return;
    }
    _blink.forward(from: 0).then((_) async {
      if (!mounted) return;
      await _blink.reverse();
      _blinking = false;
    });
  }

  @override
  void didUpdateWidget(MascotFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood && widget.animate) {
      // A mood change is a small acknowledgement, never a loop.
      _bob.forward(from: 0).then((_) {
        if (mounted) _bob.reverse();
      });
    }
  }

  @override
  void dispose() {
    _bob.removeListener(_maybeBlink);
    _bob.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final tilt = switch (widget.mood) {
      MascotMood.listening => -0.04,
      MascotMood.thinking => -0.09,
      MascotMood.happy => 0.03,
      _ => 0.0,
    };

    final face = SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(0.36, 0.46),
            radius: 0.80,
            colors: [AppTheme.mascotHighlight, AppTheme.mascotBase],
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.brand.withValues(alpha: 0.5),
              blurRadius: size * 0.4,
              offset: Offset(0, size * 0.12),
            ),
          ],
        ),
        child: ClipOval(
          child: AnimatedBuilder(
            animation: _blink,
            builder: (context, child) => Transform(
              alignment: Alignment.center,
              // The blink is a squash of the whole face: on a robot that reads
              // as eyelids, without needing a second artwork.
              transform: Matrix4.diagonal3Values(
                1,
                widget.animate ? 1 - (_blink.value * 0.88) : 1,
                1,
              ),
              child: child,
            ),
            child: Image.asset(
              'assets/mascot/mascot_face.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              // A missing asset must never take a screen down.
              errorBuilder: (context, error, stack) => ColoredBox(
                color: AppTheme.mascotBase,
                child: Center(
                  child: Icon(
                    Icons.auto_awesome,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: size * 0.42,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final bobbing = widget.animate
        ? AnimatedBuilder(
            animation: _bob,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, (_bob.value - 0.5) * size * 0.05),
              child: child,
            ),
            child: face,
          )
        : face;

    final tilted = Transform.rotate(angle: tilt, child: bobbing);

    if (!widget.glow) return tilted;

    return SizedBox(
      width: size * 1.55,
      height: size * 1.55,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.brand.withValues(alpha: 0.32),
                  AppTheme.cyan.withValues(alpha: 0.10),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 0.74],
              ),
            ),
          ),
          tilted,
        ],
      ),
    );
  }
}
