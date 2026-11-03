import 'package:flutter/material.dart';

/// Motionix brand system, extracted from the logo.
class Brand {
  Brand._();

  static const bg = Color(0xFF0A0A0F);
  static const surface = Color(0xFF15151D);
  static const surfaceHi = Color(0xFF1C1C26);
  static const border = Color(0xFF26262F);
  static const text = Color(0xFFECECF1);
  static const subtext = Color(0xFF8A8A99);

  // Logo gradient stops.
  static const azure = Color(0xFF1FA8FF);
  static const violet = Color(0xFF7C2CF2);
  static const magenta = Color(0xFFE32EF7);
  static const orange = Color(0xFFFFB424);

  static const brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [azure, violet, magenta],
  );

  static const mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['RobotoMono', 'DejaVuSansMono'],
    letterSpacing: 0.5,
  );
}

/// Text with the brand gradient swept through it.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => Brand.brandGradient.createShader(bounds),
      child: Text(text, style: style),
    );
  }
}

/// Small labelled stat chip used on the bench card.
class StatChip extends StatelessWidget {
  const StatChip({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: Brand.subtext, fontSize: 9, letterSpacing: 1)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  color: Brand.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
