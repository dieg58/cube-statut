// Signes de la charte (repris de la télécommande) : cercle ouvert, croissant, téléphone, tiret, boule.
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../cube/protocol.dart';
import 'theme.dart';

enum Sign { off, available, focus, call, disco, face, info, plus, search }

const _paths = {
  Sign.off: '<path d="M6 12h12"/>',
  Sign.available: '<circle cx="12" cy="12" r="8"/>',
  Sign.focus: '<path d="M15.5 4.2A8 8 0 1 0 19.8 15.5 6.5 6.5 0 0 1 15.5 4.2Z" fill="currentColor"/>',
  Sign.call:
      '<path d="M5 4.5h3l1.5 4-2 1.3a10 10 0 0 0 6.7 6.7l1.3-2 4 1.5v3a1.5 1.5 0 0 1-1.6 1.5A15.5 15.5 0 0 1 3.5 6.1 1.5 1.5 0 0 1 5 4.5Z"/>',
  Sign.disco:
      '<path d="M12 2v3.5"/><circle cx="12" cy="13.5" r="8"/><path d="M4 13.5h16M5.3 9.5h13.4M5.3 17.5h13.4"/><ellipse cx="12" cy="13.5" rx="3.6" ry="8"/>',
  Sign.face: '<g transform="translate(-4 -4)"><path d="M21 7.5H11.5A4 4 0 0 0 7.5 11.5v9a4 4 0 0 0 4 4h9a4 4 0 0 0 4-4V13"/></g>',
  Sign.info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
  Sign.plus: '<path d="M12 5v14M5 12h14"/>',
  Sign.search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4 4"/>',
};

Sign signFor(CubeStatus? s) => switch (s) {
      CubeStatus.off => Sign.off,
      CubeStatus.available => Sign.available,
      CubeStatus.focus => Sign.focus,
      CubeStatus.call => Sign.call,
      CubeStatus.disco => Sign.disco,
      null => Sign.face,
    };

Color signColor(Palette p, Sign s) => switch (s) {
      Sign.available => p.available,
      Sign.focus => p.focus,
      Sign.call => p.call,
      Sign.disco => p.fg,
      Sign.plus || Sign.info => p.fg,
      _ => p.fgMuted,
    };

class SignIcon extends StatelessWidget {
  const SignIcon(this.sign, {super.key, this.size = 24, this.color, this.strokeWidth = 1.5});
  final Sign sign;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final c = color ?? signColor(PaletteScope.of(context), sign);
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
        'stroke-width="$strokeWidth" stroke-linecap="round" stroke-linejoin="round">${_paths[sign]}</svg>';
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: c),
      excludeFromSemantics: true,
    );
  }
}
