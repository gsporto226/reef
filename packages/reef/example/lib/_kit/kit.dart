import 'package:flutter/widgets.dart';

/// The example's tiny design-free kit (§5: no Material, no Cupertino — core
/// widgets only). Demo-local on purpose: real apps pick their own design
/// system (material_ui is the sanctioned Material path); this one proves reef
/// needs none.

/// Bordered single-line text field over [EditableText]. The [controller] is
/// bound by the viewmodel — widgets stay pure views.
class KitField extends StatefulWidget {
  const KitField({
    super.key,
    required this.controller,
    this.label,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? label;
  final ValueChanged<String>? onSubmitted;

  @override
  State<KitField> createState() => _KitFieldState();
}

class _KitFieldState extends State<KitField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.label != null) ...[
            Text(widget.label!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
            const SizedBox(height: 4),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: _focus.hasFocus
                  ? const Color(0xFF00897B)
                  : const Color(0xFFCCCCCC)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: EditableText(
              controller: widget.controller,
              focusNode: _focus,
              cursorColor: const Color(0xFF00897B),
              backgroundCursorColor: const Color(0xFF999999),
              style: const TextStyle(
                  fontSize: 15, color: Color(0xFF222222), height: 1.2),
              onSubmitted: widget.onSubmitted,
              maxLines: 1,
            ),
          ),
        ],
      );
}

/// A flat tap target.
class KitButton extends StatelessWidget {
  const KitButton({
    super.key,
    required this.label,
    this.onPressed,
    this.filled = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final background = !enabled
        ? const Color(0xFFE0E0E0)
        : filled
            ? const Color(0xFF00897B)
            : danger
                ? const Color(0xFFB71C1C)
                : const Color(0xFFE0F2F1);
    final foreground = !enabled
        ? const Color(0xFF999999)
        : filled
            ? const Color(0xFFFFFFFF)
            : danger
                ? const Color(0xFFFFFFFF)
                : const Color(0xFF00695C);
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 14, color: foreground)),
      ),
    );
  }
}

/// App header replacing the Material AppBar.
class KitHeader extends StatelessWidget {
  const KitHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: const Color(0xFF00695C),
        child: Text(
          title,
          style: const TextStyle(fontSize: 17, color: Color(0xFFFFFFFF)),
        ),
      );
}

/// Thin separator.
class KitDivider extends StatelessWidget {
  const KitDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 12),
        color: const Color(0xFFDDDDDD),
      );
}

/// Minimal neutral spinner (a rotating square) for loading slots.
class KitSpinner extends StatefulWidget {
  const KitSpinner({super.key, this.size = 20});

  final double size;

  @override
  State<KitSpinner> createState() => _KitSpinnerState();
}

class _KitSpinnerState extends State<KitSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _rotation,
        builder: (context, _) => Transform.rotate(
          angle: _rotation.value * 6.3,
          child: Container(
            width: widget.size,
            height: widget.size,
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF00897B), width: 2),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      );
}

/// Formats a date as `yyyy-mm-dd` — the design-free stand-in for
/// MaterialLocalizations.formatShortDate.
String kitFormatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
