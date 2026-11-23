// Fenêtre principale de Kwartor pour Mac et Windows.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../cube/cube_link.dart';
import '../cube/protocol.dart';
import '../system/autostart.dart';
import 'disco.dart';
import 'signs.dart';
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.link});
  final CubeLink link;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final disco = link.connected && link.state?.status == CubeStatus.disco;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: disco ? 1 : 0),
          duration: K.turn,
          curve: K.easeTurn,
          builder: (context, t, _) {
            final palette = Palette.lerp(Palette.light, Palette.disco, t);
            return PaletteScope(
              palette: palette,
              child: Scaffold(
                backgroundColor: palette.bg,
                body: Stack(children: [
                  DiscoLayer(on: disco),
                  SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 20 + 170 * t, 24, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _Content(link: link),
                      ),
                    ),
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.link});
  final CubeLink link;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 32);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Header(link: link),
      const SizedBox(height: 24),
      _Now(link: link),
      gap,
      _CallDetection(link: link),
      gap,
      _StatusChoices(link: link),
      gap,
      _Focus(link: link),
      gap,
      _Settings(link: link),
      gap,
      const _Footer(),
    ]);
  }
}

// ------------------------------------------------------------------ en-tête
class _Header extends StatelessWidget {
  const _Header({required this.link});
  final CubeLink link;

  String get _state => switch (link.phase) {
        LinkPhase.connected => link.cubeName ?? 'Connecté',
        LinkPhase.connecting => 'Connexion…',
        LinkPhase.searching => 'Recherche du cube…',
        LinkPhase.bluetoothOff => 'Bluetooth indisponible',
        LinkPhase.noCubeChosen => 'Aucun cube',
      };

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return SizedBox(
      height: 44,
      child: Row(children: [
        Semantics(
          label: 'kwartor',
          image: true,
          child: Image.asset('assets/brand/kwartor-wordmark.png', width: 128, color: p.fg, colorBlendMode: BlendMode.srcIn),
        ),
        const Spacer(),
        Text(_state, style: body(p.fgMuted, size: 13)),
      ]),
    );
  }
}

// ------------------------------------------------------------------ statut actuel
class _Now extends StatelessWidget {
  const _Now({required this.link});
  final CubeLink link;

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final s = link.state;
    String title, sub;
    Sign sign;
    if (link.phase == LinkPhase.noCubeChosen) {
      title = 'Aucun cube';
      sub = 'Choisissez votre cube pour commencer.';
      sign = Sign.face;
    } else if (!link.connected || s == null) {
      title = link.phase == LinkPhase.bluetoothOff ? 'Bluetooth' : 'Hors de portée';
      sub = link.phase == LinkPhase.bluetoothOff
          ? 'Activez le Bluetooth de cet ordinateur.'
          : 'Kwartor se reconnecte dès que le cube est allumé et à portée.';
      sign = Sign.face;
    } else {
      title = s.status?.label ?? 'Inconnu';
      final parts = <String>[
        if (s.source != null) 'Selon : ${s.source!.label}',
        '${s.battery} %${s.charging ? ' en charge' : ''}',
      ];
      sub = parts.join(' · ');
      sign = signFor(s.status);
    }

    return Semantics(
      liveRegion: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Row(children: [
            SignIcon(sign, size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: heading(p.fg, size: 40, height: 1.04, spacing: -0.025)),
                const SizedBox(height: 4),
                Text(sub, style: body(p.fgMuted, size: 14)),
              ]),
            ),
          ]),
        ),
        if (link.lastError != null && !link.connected) ...[const SizedBox(height: 16), Notice(link.lastError!)],
        if (link.phase == LinkPhase.noCubeChosen) ...[const SizedBox(height: 20), _CubePicker(link: link)],
      ]),
    );
  }
}

class _CubePicker extends StatelessWidget {
  const _CubePicker({required this.link});
  final CubeLink link;

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final cubes = link.discovered.values.toList()..sort((a, b) => (b.rssi ?? -200).compareTo(a.rssi ?? -200));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KButton(
        link.scanningForChoice ? 'Recherche en cours…' : 'Rechercher mon cube',
        primary: true,
        onPressed: link.scanningForChoice ? null : link.scanForChoice,
      ),
      if (cubes.isNotEmpty) ...[
        const SizedBox(height: 16),
        ChoiceList(children: [
          for (final c in cubes)
            ChoiceRow(
              title: c.name,
              subtitle: c.rssi == null ? null : (c.rssi! > -65 ? 'Tout près' : 'Plus loin'),
              leading: SignIcon(Sign.face, color: p.fg),
              onTap: () => link.choose(c),
            ),
        ]),
        const Caption('Le cube le plus proche est en tête. Le nom figure sous le cube.'),
      ] else if (link.scanningForChoice)
        const Caption('Allumez le cube et approchez-le de l\'ordinateur.'),
    ]);
  }
}

// ------------------------------------------------------------------ détection d'appel
class _CallDetection extends StatelessWidget {
  const _CallDetection({required this.link});
  final CubeLink link;

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final active = link.autoDetect && link.callDetected;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Eyebrow('Appels'),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: active ? p.fg : p.line, width: active ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KSwitchRow(
            label: 'Détection automatique des appels',
            value: link.autoDetect,
            onChanged: link.setAutoDetect,
          ),
          const SizedBox(height: 8),
          Row(children: [
            SignIcon(active ? Sign.call : Sign.off, size: 20, color: active ? p.fg : p.fgMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                link.autoDetect ? link.media.describe() : 'Détection désactivée',
                style: body(active ? p.fg : p.fgMuted, size: 14, weight: active ? 500 : 400),
              ),
            ),
          ]),
        ]),
      ),
      const Caption(
          'Dès que le micro ou la caméra sont utilisés (Teams, Zoom, Meet, WhatsApp…), le cube passe en « En appel ». Il revient à son statut quelques secondes après la fin de l\'appel.'),
    ]);
  }
}

// ------------------------------------------------------------------ choix du statut
class _StatusChoices extends StatelessWidget {
  const _StatusChoices({required this.link});
  final CubeLink link;

  @override
  Widget build(BuildContext context) {
    final s = link.state;
    final on = link.connected;
    bool sel(CubeStatus st) => s?.status == st && s?.source == StatusSource.remote;
    final faceSel = s?.source == StatusSource.face;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Eyebrow('Choisir un statut'),
      ChoiceList(children: [
        ChoiceRow(
          title: 'Disponible',
          leading: const SignIcon(Sign.available),
          selected: sel(CubeStatus.available),
          onTap: on ? () => link.setStatus(CubeStatus.available) : null,
        ),
        ChoiceRow(
          title: 'Concentration',
          leading: const SignIcon(Sign.focus),
          selected: sel(CubeStatus.focus),
          onTap: on ? () => link.setStatus(CubeStatus.focus) : null,
        ),
        ChoiceRow(
          title: 'En appel',
          leading: const SignIcon(Sign.call),
          selected: sel(CubeStatus.call),
          onTap: on ? () => link.setStatus(CubeStatus.call) : null,
        ),
        ChoiceRow(
          title: 'Face du cube',
          subtitle: 'Rend la main au cube',
          leading: const SignIcon(Sign.face),
          selected: faceSel,
          onTap: on ? link.backToFace : null,
        ),
        ChoiceRow(
          title: 'Mode disco',
          subtitle: 'Pour la fin de journée',
          leading: const SignIcon(Sign.disco),
          selected: s?.status == CubeStatus.disco,
          accent: K.amber,
          onTap: on ? () => link.setStatus(s?.status == CubeStatus.disco ? CubeStatus.available : CubeStatus.disco) : null,
        ),
      ]),
      const Caption('Retourner le cube annule toujours un choix fait ici.'),
    ]);
  }
}

// ------------------------------------------------------------------ mode focus
class _Focus extends StatefulWidget {
  const _Focus({required this.link});
  final CubeLink link;
  @override
  State<_Focus> createState() => _FocusState();
}

class _FocusState extends State<_Focus> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.link.state?.session != null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.link.state?.session;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Eyebrow('Mode focus'),
      if (session != null && widget.link.connected) _Run(link: widget.link, s: session) else _Setup(link: widget.link),
    ]);
  }
}

class _Setup extends StatelessWidget {
  const _Setup({required this.link});
  final CubeLink link;

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    Widget tick(bool on) => Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? p.fg : p.control, width: 1.5)),
          alignment: Alignment.center,
          child: AnimatedScale(
            scale: on ? 1 : 0,
            duration: K.ui,
            child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: p.fg)),
          ),
        );
    Widget num(String n) => SizedBox(width: 44, child: Text(n, style: heading(p.fg, height: 1)));
    final custom = link.customMethod;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ChoiceList(children: [
        for (final m in kFocusMethods)
          ChoiceRow(
            title: m.name,
            subtitle: m.description,
            leading: num('${m.work}'),
            trailing: tick(link.focusMethodId == m.id),
            selected: link.focusMethodId == m.id,
            onTap: () => link.selectMethod(m.id),
          ),
        ChoiceRow(
          title: 'Personnalisé',
          subtitle: 'Vos propres durées',
          leading: num('${custom.work}'),
          trailing: tick(link.focusMethodId == 'custom'),
          selected: link.focusMethodId == 'custom',
          onTap: () => link.selectMethod('custom'),
        ),
      ]),
      if (link.focusMethodId == 'custom')
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _CustomFields(link: link),
        ),
      const SizedBox(height: 20),
      KButton('Lancer la session', primary: true, onPressed: link.connected ? link.startFocus : null),
      const Caption(
          'Le minuteur tourne dans le cube : vous pouvez fermer cette fenêtre. Pendant le travail, le cube affiche Concentration ; pendant les pauses, Disponible. Retourner le cube arrête la session.'),
    ]);
  }
}

class _CustomFields extends StatelessWidget {
  const _CustomFields({required this.link});
  final CubeLink link;

  @override
  Widget build(BuildContext context) {
    final m = link.customMethod;
    Widget field(String label, int value, int min, int max, FocusMethod Function(int) apply) =>
        _NumberField(label: label, value: value, min: min, max: max, onChanged: (v) => link.setCustom(apply(v)));
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 12,
      childAspectRatio: 2.4,
      children: [
        field('Travail (min)', m.work, 1, 240, (v) => m.copyWith(work: v)),
        field('Pause (min)', m.shortBreak, 0, 60, (v) => m.copyWith(shortBreak: v)),
        field('Longue pause (min)', m.longBreak, 0, 60, (v) => m.copyWith(longBreak: v)),
        field('Blocs avant la longue pause', m.blocks, 1, 12, (v) => m.copyWith(blocks: v)),
      ],
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  final String label;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _c = TextEditingController(text: '${widget.value}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.control));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: body(p.fgMuted, size: 13, height: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 6),
      Expanded(
        child: TextField(
          controller: _c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
          style: body(p.fg, size: 16),
          cursorColor: p.fg,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            enabledBorder: border,
            focusedBorder: border.copyWith(borderSide: BorderSide(color: p.fg, width: 1.5)),
          ),
          onChanged: (t) {
            final v = int.tryParse(t);
            if (v != null) widget.onChanged(v.clamp(widget.min, widget.max));
          },
          onEditingComplete: () {
            final v = (int.tryParse(_c.text) ?? widget.min).clamp(widget.min, widget.max);
            _c.text = '$v';
            widget.onChanged(v);
            FocusScope.of(context).unfocus();
          },
        ),
      ),
    ]);
  }
}

class _Run extends StatelessWidget {
  const _Run({required this.link, required this.s});
  final CubeLink link;
  final FocusSession s;

  static String mmss(int sec) => '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final now = DateTime.now();
    final left = s.remainingAt(now);
    final work = s.phase == FocusPhase.work;
    final phaseName = switch (s.phase) {
      FocusPhase.work => 'Travail',
      FocusPhase.shortBreak => 'Pause',
      FocusPhase.longBreak => 'Longue pause',
      FocusPhase.none => 'Session',
    };
    final blocksLabel = s.blocksBeforeLong > 0 ? ' · bloc ${s.block} sur ${s.blocksBeforeLong}' : ' · bloc ${s.block}';
    final next = switch (s.phase) {
      FocusPhase.work => s.blocksBeforeLong > 0 && s.block >= s.blocksBeforeLong ? 'Ensuite : longue pause' : 'Ensuite : pause',
      FocusPhase.shortBreak => 'Ensuite : travail',
      FocusPhase.longBreak => 'Dernière phase de la série',
      FocusPhase.none => '',
    };
    final total = s.blocksBeforeLong > 0 ? s.blocksBeforeLong : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        SignIcon(work ? Sign.focus : Sign.available, size: 22),
        const SizedBox(width: 10),
        Text('$phaseName$blocksLabel', style: body(p.fg, weight: 500)),
      ]),
      const SizedBox(height: 16),
      Semantics(
        label: '$phaseName, ${left ~/ 60} minutes ${left % 60} secondes restantes',
        excludeSemantics: true,
        child: Text(mmss(left), style: heading(p.fg, size: 72, height: 1, spacing: -0.03)),
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, c) => Stack(children: [
          Container(height: 1.5, color: p.line),
          AnimatedContainer(
            duration: const Duration(seconds: 1),
            height: 1.5,
            width: c.maxWidth * s.progressAt(now).clamp(0.0, 1.0),
            color: p.fg,
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: Text(next, style: body(p.fgMuted, size: 13))),
        for (var i = 1; i <= total; i++)
          Container(
            margin: const EdgeInsets.only(left: 6),
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (i < s.block || (i == s.block && !work)) ? p.fg : Colors.transparent,
              border: Border.all(color: i <= s.block ? p.fg : p.control, width: i == s.block && work ? 3 : 1.5),
            ),
          ),
      ]),
      const SizedBox(height: 20),
      KButton('Arrêter la session', onPressed: link.stopFocus),
    ]);
  }
}

// ------------------------------------------------------------------ réglages
class _Settings extends StatefulWidget {
  const _Settings({required this.link});
  final CubeLink link;
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  bool? _autostart;
  double? _dragBrightness;

  @override
  void initState() {
    super.initState();
    autostartEnabled().then((v) => mounted ? setState(() => _autostart = v) : null);
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final p = PaletteScope.of(context);
    final on = link.connected;
    final bri = _dragBrightness ?? link.brightness.toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Eyebrow('Réglages'),
      Row(children: [
        Expanded(child: Text('Luminosité', style: body(p.fg))),
        Text('${bri.round()} %', style: body(p.fgMuted)),
      ]),
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 1.5,
          activeTrackColor: p.fg,
          inactiveTrackColor: p.fg,
          disabledActiveTrackColor: p.control,
          disabledInactiveTrackColor: p.control,
          thumbColor: p.bg,
          overlayShape: SliderComponentShape.noOverlay,
          thumbShape: _RingThumb(p.fg, p.bg),
          tickMarkShape: SliderTickMarkShape.noTickMark,
          showValueIndicator: ShowValueIndicator.never,
        ),
        child: SizedBox(
          height: 44,
          child: Slider(
            value: bri.clamp(5, 40),
            min: 5,
            max: 40,
            divisions: 7,
            semanticFormatterCallback: (v) => '${v.round()} %',
            onChanged: on
                ? (v) {
                    setState(() => _dragBrightness = v);
                    link.setBrightness(v.round(), persist: false);
                  }
                : null,
            onChangeEnd: (v) {
              setState(() => _dragBrightness = null);
              link.setBrightness(v.round());
            },
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text('Durée de la concentration', style: body(p.fg))),
        _Dropdown(
          value: link.focusDuration,
          items: const {30: '30 min', 60: '1 h', 90: '1 h 30', 120: '2 h'},
          onChanged: on ? link.setFocusDuration : null,
        ),
      ]),
      const SizedBox(height: 20),
      KSwitchRow(
        label: 'Lancer Kwartor à l\'ouverture de session',
        value: _autostart ?? false,
        onChanged: _autostart == null
            ? null
            : (v) async {
                final ok = await setAutostart(v);
                final now = await autostartEnabled();
                if (mounted) setState(() => _autostart = now);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Réglage impossible sur ce système.')),
                  );
                }
              },
      ),
      const SizedBox(height: 24),
      Fold(
        title: 'Programmer les faces',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Caption('Posez le cube sur la face à programmer, attendez une seconde, puis choisissez le statut qu\'elle doit afficher.', top: 0),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 3.6,
            children: [
              for (final st in [CubeStatus.available, CubeStatus.focus, CubeStatus.call, CubeStatus.off])
                KButton(st.label, compact: true, onPressed: on ? () => link.learnFace(st) : null),
            ],
          ),
        ]),
      ),
      Fold(
        title: 'Mon cube',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Info('Nom', link.cubeName ?? '-'),
          _Info('Batterie', link.state == null ? '-' : '${link.state!.battery} %${link.state!.charging ? ' (en charge)' : ''}'),
          _Info('Logiciel du cube', link.firmware ?? '-'),
          const SizedBox(height: 12),
          KButton(
            'Changer de cube',
            compact: true,
            onPressed: link.cubeId == null ? null : link.forget,
          ),
          const Caption('Kwartor oublie ce cube et vous propose de rechercher le vôtre.'),
        ]),
      ),
    ]);
  }
}

class _Info extends StatelessWidget {
  const _Info(this.k, this.v);
  final String k, v;
  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(k, style: body(p.fgMuted, size: 14))),
        Text(v, style: body(p.fg, size: 14)),
      ]),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.value, required this.items, required this.onChanged});
  final int value;
  final Map<int, String> items;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border.all(color: p.control), borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: items.containsKey(value) ? value : items.keys.first,
          dropdownColor: p.bg,
          style: body(onChanged == null ? p.fgMuted : p.fg),
          iconEnabledColor: p.fg,
          iconDisabledColor: p.fgMuted,
          items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: onChanged == null ? null : (v) => v == null ? null : onChanged!(v),
        ),
      ),
    );
  }
}

class _RingThumb extends SliderComponentShape {
  const _RingThumb(this.ring, this.fill);
  final Color ring, fill;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size.square(28);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final c = context.canvas;
    final color = enableAnimation.value < 1 ? sliderTheme.disabledActiveTrackColor ?? ring : ring;
    c.drawCircle(center, 14, Paint()..color = fill);
    c.drawCircle(center, 13.25, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color);
  }
}

// ------------------------------------------------------------------ pied
class _Footer extends StatelessWidget {
  const _Footer();
  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Container(
      padding: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
      child: Text('A quarter turn, and they know.', style: heading(p.fg, size: 22)),
    );
  }
}
