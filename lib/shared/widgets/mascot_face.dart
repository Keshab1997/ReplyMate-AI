import 'package:material_ui/material_ui.dart';

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
    this.semanticLabel,
    super.key,
  });

  final double size;
  final MascotMood mood;

  /// The soft radial halo behind the disc.
  final bool glow;

  /// Off for tests and for the small headers where motion would be noise.
  final bool animate;

  /// The picture is decoration, so by default it is hidden from TalkBack.
  /// Pass a label only when the face itself carries meaning ("Thinking").
  final String? semanticLabel;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  /// Whether the platform currently wants motion: the widget's own switch AND
  /// Android's "Remove animations" setting. A stopped controller schedules no
  /// frames at all, so honouring the setting actually saves the work instead of
  /// only freezing the picture.
  bool get _shouldMove {
    if (!widget.animate) return false;
    return !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  }

  void _syncMotion() {
    if (_shouldMove && !_bob.isAnimating) {
      _bob.repeat(reverse: true, count: _cycles);
    } else if (!_shouldMove && (_bob.isAnimating || _blink.isAnimating)) {
      _bob.stop();
      _blink.stop();
      _bob.value = 0;
      _blink.value = 0;
    }
  }

  /// One blink roughly every third bob, so it never looks like a metronome.
  void _maybeBlink() {
    if (!widget.animate || _blinking) return;
    if (widget.mood != MascotMood.idle && widget.mood != MascotMood.listening) {
      return;
    }
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
    if (oldWidget.animate != widget.animate) _syncMotion();
    if (oldWidget.mood != widget.mood && _shouldMove) {
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
    // "Remove animations" in Android settings is a real preference, not a
    // developer toggle: honour it everywhere, including the decorating bob.
    final moving = _shouldMove;
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
            builder: (context, child) => Stack(
              fit: StackFit.expand,
              children: [
                child!,
                // A real eyelid frame, not a squash of the whole robot. The
                // image only exists during the blink, so the resting tree and
                // semantics stay exactly as light as before.
                if (moving && _blink.value > 0)
                  Opacity(
                    opacity: _blink.value,
                    child: Image.asset(
                      'assets/mascot/mascot_face_blink.png',
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, error, stack) =>
                          const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
            child: Image.asset(
              switch (widget.mood) {
                MascotMood.happy => 'assets/mascot/mascot_face_happy.png',
                MascotMood.alert => 'assets/mascot/mascot_face_alert.png',
                _ => 'assets/mascot/mascot_face.png',
              },
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

    final bobbing = moving
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

    final thinking = widget.mood == MascotMood.thinking;

    if (!widget.glow) {
      return _described(
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              tilted,
              if (thinking)
                Positioned(
                  bottom: 0,
                  child: _ThinkingDots(size: size, animate: moving),
                ),
            ],
          ),
        ),
      );
    }

    return _described(
      SizedBox(
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
            if (thinking)
              Positioned(
                bottom: size * 0.12,
                child: _ThinkingDots(size: size, animate: moving),
              ),
          ],
        ),
      ),
    );
  }

  /// Decoration by default: a TalkBack user should not hear "image" between
  /// two sentences. A caller that gives the face meaning passes a label.
  Widget _described(Widget child) {
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: child);
    return Semantics(image: true, label: label, child: child);
  }
}

/// Three dots that breathe in sequence under the face.
/// This is the app's only "the helper is working" cue, and it is deliberately
/// wordless: it says *something is happening* without pretending to know how
/// long it will take or what the answer will be. Finite like every other
/// animation here, so a widget test can settle it.
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots({required this.size, required this.animate});

  final double size;
  final bool animate;

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat(count: 6);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = widget.size * 0.085;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          key: const Key('mascot-thinking-dots'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: dot * 0.38),
                child: Opacity(
                  opacity: _phase(i),
                  child: Container(
                    width: dot,
                    height: dot,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Each dot lags the previous one by a sixth of the cycle, so the row reads
  /// as a wave rather than a blink.
  double _phase(int index) {
    if (!widget.animate) return 0.75;
    final t = (_controller.value + index * 0.16) % 1.0;
    return 0.30 + 0.70 * (1 - (2 * t - 1).abs());
  }
}
