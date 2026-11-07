import 'package:flutter/material.dart';

/// Logo Vektor MusEvee (100% Transparent Background)
/// Identik secara matematis dengan ikon launcher Android di `mipmap-*/ic_launcher.png`.
class MusEveeLogo extends StatelessWidget {
  final double size;

  const MusEveeLogo({
    super.key,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MusEveeLogoPainter(),
      ),
    );
  }
}

class _MusEveeLogoPainter extends CustomPainter {
  static const Color _primaryBlue = Color(0xFF1677B8);
  static const Color _deepBlue = Color(0xFF0E5E93);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = Radius.circular(w * 0.045);

    final primaryPaint = Paint()
      ..color = _primaryBlue
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final deepPaint = Paint()
      ..color = _deepBlue
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final primaryBridgePaint = Paint()
      ..color = _primaryBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final deepBridgePaint = Paint()
      ..color = _deepBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // Jembatan diagonal huruf M
    canvas.drawLine(
      Offset(w * 0.15, h * 0.24),
      Offset(w * 0.40, h * 0.52),
      primaryBridgePaint,
    );
    canvas.drawLine(
      Offset(w * 0.40, h * 0.52),
      Offset(w * 0.65, h * 0.24),
      deepBridgePaint,
    );

    // 3 lengan horizontal huruf E / gelombang equalizer
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.59, h * 0.18, w * 0.91, h * 0.30),
        r,
      ),
      primaryPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.59, h * 0.44, w * 0.86, h * 0.56),
        r,
      ),
      primaryPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.59, h * 0.70, w * 0.91, h * 0.82),
        r,
      ),
      deepPaint,
    );

    // 3 pilar gelombang suara vertikal (M + E)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.09, h * 0.18, w * 0.21, h * 0.82),
        r,
      ),
      primaryPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.34, h * 0.10, w * 0.46, h * 0.82),
        r,
      ),
      primaryPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.59, h * 0.18, w * 0.71, h * 0.82),
        r,
      ),
      deepPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

