import 'package:material_ui/material_ui.dart';

/// ReplyMate's small custom line-icon set. These cover product ideas that
/// generic Material icons only approximate, while keeping the same rounded
/// stroke at every size.
enum BrandIconType {
  reply,
  notification,
  language,
  privacy,
  screenReading,
  memory,
}

class BrandIcon extends StatelessWidget {
  const BrandIcon({
    required this.type,
    required this.color,
    this.size = 20,
    this.semanticLabel,
    super.key,
  });

  final BrandIconType type;
  final Color color;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final icon = CustomPaint(
      size: Size.square(size),
      painter: _BrandIconPainter(type: type, color: color),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: icon);
    return Semantics(image: true, label: label, child: icon);
  }
}

class _BrandIconPainter extends CustomPainter {
  const _BrandIconPainter({required this.type, required this.color});

  final BrandIconType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (type) {
      case BrandIconType.reply:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(3, 4, 16, 15),
            const Radius.circular(3),
          ),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(7, 15)
            ..lineTo(6, 19)
            ..lineTo(11, 15),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(18.5, 3)
            ..lineTo(18.5, 8)
            ..moveTo(16, 5.5)
            ..lineTo(21, 5.5)
            ..moveTo(17, 2)
            ..lineTo(20, 9),
          line,
        );
      case BrandIconType.notification:
        canvas.drawPath(
          Path()
            ..moveTo(6, 16)
            ..lineTo(18, 16)
            ..moveTo(7.5, 16)
            ..lineTo(7.5, 11)
            ..cubicTo(7.5, 7.5, 9, 5, 12, 5)
            ..cubicTo(15, 5, 16.5, 7.5, 16.5, 11)
            ..lineTo(16.5, 16)
            ..moveTo(10, 19)
            ..cubicTo(10.8, 20, 13.2, 20, 14, 19)
            ..moveTo(12, 2.5)
            ..lineTo(12, 4),
          line,
        );
        canvas.drawCircle(const Offset(19, 5), 2, line);
      case BrandIconType.language:
        canvas.drawCircle(const Offset(12, 12), 9, line);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(12, 12), width: 9, height: 18),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(3.5, 9)
            ..lineTo(20.5, 9)
            ..moveTo(3.5, 15)
            ..lineTo(20.5, 15),
          line,
        );
      case BrandIconType.privacy:
        canvas.drawPath(
          Path()
            ..moveTo(12, 3)
            ..lineTo(19, 6)
            ..lineTo(19, 11)
            ..cubicTo(19, 16, 16, 19, 12, 21)
            ..cubicTo(8, 19, 5, 16, 5, 11)
            ..lineTo(5, 6)
            ..close(),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(8.5, 12)
            ..lineTo(11, 14.5)
            ..lineTo(15.8, 9.5),
          line,
        );
      case BrandIconType.screenReading:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(2.5, 4, 21.5, 20),
            const Radius.circular(4),
          ),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(6, 12)
            ..cubicTo(8.5, 8.5, 15.5, 8.5, 18, 12)
            ..cubicTo(15.5, 15.5, 8.5, 15.5, 6, 12)
            ..close(),
          line,
        );
        canvas.drawCircle(const Offset(12, 12), 1.5, fill);
      case BrandIconType.memory:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(3, 3, 18, 15),
            const Radius.circular(3),
          ),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(7, 7)
            ..lineTo(14, 7)
            ..moveTo(7, 10.5)
            ..lineTo(12, 10.5)
            ..moveTo(7, 15)
            ..lineTo(6, 18),
          line,
        );
        canvas.drawCircle(const Offset(17.5, 17.5), 4, line);
        canvas.drawPath(
          Path()
            ..moveTo(17.5, 15.5)
            ..lineTo(17.5, 18)
            ..lineTo(19, 19),
          line,
        );
    }
  }

  @override
  bool shouldRepaint(_BrandIconPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}
