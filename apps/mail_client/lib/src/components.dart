// The design's components (design/SPEC.md, Components), drawn from the
// generated tokens and glyphs. Values come from the spec; every one that is
// not a token is a spec literal (content-driven sizes, Open issues 3).
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mail_client/src/icons.g.dart';
import 'package:mail_client/src/tokens.g.dart';

export 'package:mail_client/src/icons.g.dart';
export 'package:mail_client/src/tokens.g.dart';

typedef T = MailTokens;

/// The spec's text styles, named after the design's.
abstract final class MailText {
  static const _serif = 'Source Serif 4', _sans = 'Source Sans 3';
  static const _semibold = FontWeight.w600;

  static const serifDisplay32 = TextStyle(
    fontFamily: _serif,
    fontWeight: _semibold,
    fontSize: 32,
  );
  static const serifBrand24 = TextStyle(
    fontFamily: _serif,
    fontWeight: _semibold,
    fontSize: 24,
  );
  static const serifTitle22 = TextStyle(
    fontFamily: _serif,
    fontWeight: _semibold,
    fontSize: 22,
  );
  static const serifSubject16 = TextStyle(
    fontFamily: _serif,
    fontWeight: _semibold,
    fontSize: 16,
  );
  static const sansBody16 = TextStyle(
    fontFamily: _sans,
    fontSize: 16,
    height: 1.6,
  );
  static const sansLabelStrong15 = TextStyle(
    fontFamily: _sans,
    fontWeight: _semibold,
    fontSize: 15,
  );
  static const sansLabel15 = TextStyle(fontFamily: _sans, fontSize: 15);
  static const sansStrong14 = TextStyle(
    fontFamily: _sans,
    fontWeight: _semibold,
    fontSize: 14,
  );
  static const sansRegular14 = TextStyle(fontFamily: _sans, fontSize: 14);
  static const sansCaption13 = TextStyle(fontFamily: _sans, fontSize: 13);
  static const sansCaptionStrong13 = TextStyle(
    fontFamily: _sans,
    fontWeight: _semibold,
    fontSize: 13,
  );

  /// Uppercase: write the text with [String.toUpperCase].
  static const sansOverline12 = TextStyle(
    fontFamily: _sans,
    fontWeight: _semibold,
    fontSize: 12,
  );
  static const sansMeta12 = TextStyle(fontFamily: _sans, fontSize: 12);
}

/// `Elevation/Overlay`.
const elevationOverlay = [
  BoxShadow(color: Color(0x291F1B16), offset: Offset(0, 4), blurRadius: 24),
];

const _hairline = BorderSide(color: T.borderHairline);

/// A 20x20 `Icon / *` in [color].
class Glyph extends StatelessWidget {
  const Glyph(this.glyph, {super.key, required this.color});

  final MailGlyph glyph;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: T.sizeIcon,
    child: CustomPaint(painter: _GlyphPainter(glyph, color)),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color);

  final MailGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    glyph.build(),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = MailGlyph.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color,
  );

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}

/// A tap target with no ink: the design has no pressed states.
class Tap extends StatelessWidget {
  const Tap({super.key, required this.label, this.onTap, required this.child});

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    container: true,
    excludeSemantics: true,
    child: MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    ),
  );
}

/// `Button / Primary`. Null [label] is the icon-only 44x44 use.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.glyph,
    required this.semanticLabel,
    this.label,
    this.radius = T.radiusLg,
    this.hug = false,
    this.onTap,
  });

  final MailGlyph glyph;
  final String semanticLabel;
  final String? label;
  final double radius;

  /// W hug instead of fill.
  final bool hug;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = Glyph(glyph, color: T.accentOn);
    return Tap(
      label: semanticLabel,
      onTap: onTap,
      child: Container(
        height: T.sizeControlMd,
        width: label == null ? T.sizeControlMd : (hug ? null : double.infinity),
        padding: label == null
            ? null
            : const EdgeInsets.symmetric(horizontal: T.space16),
        decoration: BoxDecoration(
          color: T.accentDefault,
          borderRadius: BorderRadius.circular(radius),
        ),
        alignment: label == null ? Alignment.center : null,
        child: label == null
            ? icon
            : Row(
                mainAxisSize: hug ? MainAxisSize.min : MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: T.space8,
                children: [
                  icon,
                  Text(
                    label!,
                    style: MailText.sansLabelStrong15.copyWith(
                      color: T.accentOn,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// `Avatar`.
class Avatar extends StatelessWidget {
  const Avatar(this.initials, {super.key});

  final String initials;

  @override
  Widget build(BuildContext context) => Container(
    width: T.sizeAvatar,
    height: T.sizeAvatar,
    decoration: BoxDecoration(
      color: T.avatarBg,
      borderRadius: BorderRadius.circular(T.radiusPill),
    ),
    alignment: Alignment.center,
    child: Text(
      initials,
      style: MailText.sansLabelStrong15.copyWith(color: T.avatarFg),
    ),
  );
}

/// `Reply bar`.
class ReplyBar extends StatelessWidget {
  const ReplyBar(this.placeholder, {super.key});

  final String placeholder;

  @override
  Widget build(BuildContext context) => Container(
    height: T.sizeControlLg,
    padding: const EdgeInsets.symmetric(horizontal: T.space16),
    decoration: BoxDecoration(
      color: T.surfaceList,
      border: Border.fromBorderSide(_hairline),
      borderRadius: BorderRadius.circular(T.radiusMd),
    ),
    alignment: Alignment.centerLeft,
    child: Text(
      placeholder,
      style: MailText.sansLabel15.copyWith(color: T.textMuted),
    ),
  );
}

/// `Folder row`. [showLabel] false is the 44x44 icon-only use.
class FolderRow extends StatelessWidget {
  const FolderRow({
    super.key,
    required this.name,
    required this.glyph,
    required this.selected,
    this.count,
    this.showLabel = true,
    this.onTap,
  });

  final String name;
  final MailGlyph glyph;
  final bool selected;

  /// Null hides the count.
  final String? count;
  final bool showLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? T.accentDefault : T.textPrimary;
    return Tap(
      label: name,
      onTap: onTap,
      child: Container(
        height: T.sizeControlMd,
        width: showLabel ? null : T.sizeControlMd,
        padding: showLabel
            ? const EdgeInsets.symmetric(horizontal: T.space12)
            : null,
        decoration: BoxDecoration(
          color: selected ? T.surfaceSelected : null,
          borderRadius: BorderRadius.circular(T.radiusSm),
        ),
        alignment: Alignment.center,
        child: !showLabel
            ? Glyph(glyph, color: color)
            : Row(
                spacing: T.space10,
                children: [
                  Glyph(glyph, color: color),
                  Expanded(
                    child: Text(
                      name,
                      style:
                          (selected
                                  ? MailText.sansLabelStrong15
                                  : MailText.sansLabel15)
                              .copyWith(color: color),
                    ),
                  ),
                  if (count != null)
                    Text(
                      count!,
                      style: MailText.sansCaptionStrong13.copyWith(
                        color: T.accentDefault,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// `Thread row`.
class ThreadRow extends StatelessWidget {
  const ThreadRow({
    super.key,
    required this.sender,
    required this.time,
    required this.subject,
    required this.preview,
    required this.unread,
    required this.selected,
    this.onTap,
  });

  final String sender, time, subject, preview;
  final bool unread, selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tap(
    label: subject,
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: T.space14,
        horizontal: T.space12,
      ),
      decoration: BoxDecoration(
        color: selected ? T.surfaceSelected : null,
        borderRadius: BorderRadius.circular(T.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: T.space4,
        children: [
          Row(
            spacing: T.space8,
            children: [
              if (unread)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: T.accentDefault,
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  sender,
                  style: MailText.sansStrong14.copyWith(color: T.textPrimary),
                ),
              ),
              Text(
                time,
                style: MailText.sansMeta12.copyWith(color: T.textMuted),
              ),
            ],
          ),
          Text(
            subject,
            style: MailText.serifSubject16.copyWith(color: T.textPrimary),
          ),
          SizedBox(
            height: 15,
            child: ClipRect(
              child: Text(
                preview,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: MailText.sansRegular14.copyWith(color: T.textMuted),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// `Search bar`; [width] null fills. The placeholder shows while
/// [controller] is empty.
class MailSearchBar extends StatelessWidget {
  const MailSearchBar({
    super.key,
    this.width,
    required this.controller,
    this.onChanged,
  });

  final double? width;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: T.sizeControlSm,
    padding: const EdgeInsets.symmetric(horizontal: T.space16),
    decoration: BoxDecoration(
      color: T.surfaceField,
      border: Border.fromBorderSide(_hairline),
      borderRadius: BorderRadius.circular(T.radiusPill),
    ),
    child: Row(
      spacing: T.space8,
      children: [
        const Glyph(MailGlyph.search, color: T.textMuted),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: MailText.sansMeta12.copyWith(color: T.textPrimary),
            decoration: InputDecoration.collapsed(
              hintText: 'Search mail',
              hintStyle: MailText.sansMeta12.copyWith(color: T.textMuted),
            ),
          ),
        ),
      ],
    ),
  );
}

/// `Compose field`: a [label] column and an editable value.
class ComposeField extends StatelessWidget {
  const ComposeField({super.key, required this.label, required this.value});

  final String label;
  final TextEditingController value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: T.space12),
    decoration: const BoxDecoration(border: Border(bottom: _hairline)),
    child: Row(
      spacing: T.space12,
      children: [
        SizedBox(
          width: T.composeFieldLabelWidth,
          child: Text(
            label,
            style: MailText.sansMeta12.copyWith(color: T.textMuted),
          ),
        ),
        Expanded(
          child: TextField(
            controller: value,
            style: MailText.sansMeta12.copyWith(color: T.textPrimary),
            decoration: InputDecoration.collapsed(hintText: null),
          ),
        ),
      ],
    ),
  );
}

/// `Back link`.
class BackLink extends StatelessWidget {
  const BackLink({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Tap(
      label: 'Back to $label',
      onTap: onTap,
      child: Container(
        height: T.sizeControlMd,
        padding: const EdgeInsets.fromLTRB(T.space4, 0, T.space8, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(T.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: T.space4,
          children: [
            const Glyph(MailGlyph.chevronLeft, color: T.accentDefault),
            Text(
              label,
              style: MailText.sansMeta12.copyWith(color: T.accentDefault),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A 44x44 icon-only control: `Nav toggle`, the sidebar hit areas, Close.
class IconControl extends StatelessWidget {
  const IconControl(
    this.glyph, {
    super.key,
    required this.label,
    this.radius = 0,
    this.onTap,
  });

  final MailGlyph glyph;
  final String label;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tap(
    label: label,
    onTap: onTap,
    child: SizedBox.square(
      dimension: T.sizeControlMd,
      child: Center(child: Glyph(glyph, color: T.textMuted)),
    ),
  );
}

/// A pane on [color] with the `Surface/Paper` noise as a full-bleed layer
/// behind [child].
class Paper extends StatelessWidget {
  const Paper({super.key, required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: CustomPaint(painter: _PaperPainter(), child: child),
  );
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter();

  static const _tile = 64;

  /// Mono noise, density 0.15: dots in `#6B4F33` @ 4% over `#FFFFFF` @ 25%,
  /// one tile reused by every pane.
  // ponytail: our own seeded noise, not FigCraft's generator; see SPEC.md
  // Open issues.
  static final ui.Image _noise = () {
    final rng = Random(7);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        Rect.fromLTWH(0, 0, _tile.toDouble(), _tile.toDouble()),
        Paint()..color = const Color(0x40FFFFFF),
      );
    final dot = Paint()..color = const Color(0x0A6B4F33);
    for (var y = 0; y < _tile; y++) {
      for (var x = 0; x < _tile; x++) {
        if (rng.nextDouble() < 0.15) {
          canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), dot);
        }
      }
    }
    return recorder.endRecording().toImageSync(_tile, _tile);
  }();

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ImageShader(
        _noise,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.identity().storage,
      )
      ..blendMode = BlendMode.multiply
      ..color = const Color(0x08000000), // layer opacity 3%
  );

  @override
  bool shouldRepaint(_PaperPainter old) => false;
}

/// The bottom (or top) 1px `border/hairline`, inside the box's layout.
BoxDecoration hairlineBar({bool top = false}) => BoxDecoration(
  color: T.surfaceList,
  border: top ? const Border(top: _hairline) : const Border(bottom: _hairline),
);

/// A right 1px `border/hairline` drawn over the box, not in its layout.
const rightHairline = BoxDecoration(border: Border(right: _hairline));

/// The 1px inside `border/hairline` of the nav pill.
const hairlineAll = Border.fromBorderSide(_hairline);
