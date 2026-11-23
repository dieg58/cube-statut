// Charte Kwartor : papier / encre, bleu « Disponible », ambre « Concentration », encre « En appel ».
// Palette Okabe-Ito, choisie pour rester lisible en cas de daltonisme. Jamais la couleur seule : chaque statut a son signe.

import 'package:material_ui/material_ui.dart';

abstract final class K {
  static const paper = Color(0xFFF7F5F0);
  static const ink = Color(0xFF0B1B2B);
  static const blue = Color(0xFF0072B2);
  static const amber = Color(0xFFE69F00);
  static const muted = Color(0xFF52616D);
  static const line = Color(0xFFDCE0DE);
  static const control = Color(0xFF7A858D);
  static const inkHover = Color(0xFF263746);
  static const sky = Color(0xFF56B4E9);

  static const turn = Duration(milliseconds: 420);
  static const ui = Duration(milliseconds: 180);
  static const easeTurn = Cubic(.22, 1, .36, 1);
}

/// Jeu de couleurs courant : clair, ou sombre en mode disco.
class Palette {
  const Palette({
    required this.bg,
    required this.fg,
    required this.fgMuted,
    required this.line,
    required this.control,
    required this.primaryBg,
    required this.primaryFg,
    required this.available,
    required this.focus,
    required this.call,
  });

  final Color bg, fg, fgMuted, line, control, primaryBg, primaryFg, available, focus, call;

  static const light = Palette(
    bg: K.paper,
    fg: K.ink,
    fgMuted: K.muted,
    line: K.line,
    control: K.control,
    primaryBg: K.ink,
    primaryFg: K.paper,
    available: K.blue,
    focus: K.amber,
    call: K.ink,
  );

  static const disco = Palette(
    bg: K.ink,
    fg: K.paper,
    fgMuted: Color(0xFFAEB8C0),
    line: Color(0xFF33475A),
    control: K.control,
    primaryBg: K.paper,
    primaryFg: K.ink,
    available: K.sky,
    focus: K.amber,
    call: K.paper,
  );

  static Palette lerp(Palette a, Palette b, double t) => Palette(
        bg: Color.lerp(a.bg, b.bg, t)!,
        fg: Color.lerp(a.fg, b.fg, t)!,
        fgMuted: Color.lerp(a.fgMuted, b.fgMuted, t)!,
        line: Color.lerp(a.line, b.line, t)!,
        control: Color.lerp(a.control, b.control, t)!,
        primaryBg: Color.lerp(a.primaryBg, b.primaryBg, t)!,
        primaryFg: Color.lerp(a.primaryFg, b.primaryFg, t)!,
        available: Color.lerp(a.available, b.available, t)!,
        focus: Color.lerp(a.focus, b.focus, t)!,
        call: Color.lerp(a.call, b.call, t)!,
      );
}

class PaletteScope extends InheritedWidget {
  const PaletteScope({super.key, required this.palette, required super.child});
  final Palette palette;

  static Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaletteScope>()?.palette ?? Palette.light;

  @override
  bool updateShouldNotify(PaletteScope old) => old.palette != palette;
}

TextStyle body(Color c, {double size = 15, double weight = 400, double height = 1.45}) => TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      height: height,
      color: c,
      fontVariations: [FontVariation('wght', weight)],
      fontWeight: weight >= 500 ? FontWeight.w500 : FontWeight.w400,
    );

TextStyle heading(Color c, {double size = 22, double height = 1.15, double spacing = -0.02}) => TextStyle(
      fontFamily: 'Newsreader',
      fontSize: size,
      height: height,
      letterSpacing: size * spacing,
      color: c,
      fontVariations: const [FontVariation('wght', 400)],
      fontFeatures: const [FontFeature.tabularFigures()],
    );

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: K.paper,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.light(primary: K.ink, onPrimary: K.paper, surface: K.paper, onSurface: K.ink),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: K.ink.withValues(alpha: .04),
      focusColor: K.blue.withValues(alpha: .12),
    );
