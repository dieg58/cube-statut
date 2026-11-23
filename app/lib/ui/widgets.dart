// Composants de base, dessinés d'après la télécommande Kwartor (filets 1 px, pas d'aplats décoratifs).
import 'package:material_ui/material_ui.dart';

import 'signs.dart';
import 'theme.dart';

class KButton extends StatelessWidget {
  const KButton(this.label, {super.key, this.onPressed, this.primary = false, this.compact = false});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final enabled = onPressed != null;
    final bg = primary && enabled ? p.primaryBg : Colors.transparent;
    final fg = !enabled ? p.fgMuted : (primary ? p.primaryFg : p.fg);
    final border = enabled ? p.primaryBg : p.control;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 44 : 52),
            padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24, vertical: 10),
            alignment: Alignment.center,
            child: Text(label, textAlign: TextAlign.center, style: body(fg, weight: 500, height: 1.3)),
          ),
        ),
      ),
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: body(PaletteScope.of(context).fgMuted, size: 14, weight: 500, height: 1.3)),
      );
}

class Caption extends StatelessWidget {
  const Caption(this.text, {super.key, this.top = 12});
  final String text;
  final double top;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top),
        child: Text(text, style: body(PaletteScope.of(context).fgMuted, size: 13)),
      );
}

/// Liste à filets : une ligne par choix, filet gauche de 2 px pour l'élément actif.
class ChoiceList extends StatelessWidget {
  const ChoiceList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
      child: Column(
        children: [
          for (final c in children)
            DecoratedBox(decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))), child: c),
        ],
      ),
    );
  }
}

class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.accent,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final enabled = onTap != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: InkWell(
        onTap: onTap,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: AnimatedContainer(
          duration: K.ui,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: selected ? (accent ?? p.fg) : Colors.transparent, width: 2)),
          ),
          child: Row(children: [
            if (leading != null) ...[
              Opacity(opacity: enabled ? 1 : .5, child: leading!),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: body(enabled ? p.fg : p.fgMuted, size: 17, weight: 500, height: 1.3)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: body(p.fgMuted, size: 13, height: 1.35)),
                  ),
              ]),
            ),
            ?trailing,
          ]),
        ),
      ),
    );
  }
}

class KSwitchRow extends StatelessWidget {
  const KSwitchRow({super.key, required this.label, required this.value, required this.onChanged, this.caption});
  final String label;
  final String? caption;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return MergeSemantics(
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: body(p.fg)),
            if (caption != null) Caption(caption!, top: 2),
          ]),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: p.primaryFg,
          activeTrackColor: p.primaryBg,
          inactiveThumbColor: p.control,
          inactiveTrackColor: p.bg,
          trackOutlineColor: WidgetStatePropertyAll(value ? p.primaryBg : p.control),
        ),
      ]),
    );
  }
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: p.control), borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: SignIcon(Sign.info, size: 20, color: p.fg)),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: body(p.fg))),
      ]),
    );
  }
}

/// Bloc dépliable « + » (équivalent de l'élément details de la télécommande).
class Fold extends StatefulWidget {
  const Fold({super.key, required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  State<Fold> createState() => _FoldState();
}

class _FoldState extends State<Fold> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Container(
      decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: p.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() => open = !open),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Row(children: [
              Expanded(child: Text(widget.title, style: heading(p.fg))),
              AnimatedRotation(turns: open ? .125 : 0, duration: K.ui, child: SignIcon(Sign.plus, color: p.fg)),
            ]),
          ),
        ),
        AnimatedSize(
          duration: K.ui,
          alignment: Alignment.topCenter,
          child: open ? Padding(padding: const EdgeInsets.only(bottom: 24), child: widget.child) : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}
