// =========================================================
//  tv_black_box_screen.dart — Écran « Boîte noire » (Réglages)
// =========================================================
//  Lecture à la télécommande de l'enregistreur de vol (core/blackbox) :
//    • en tête : la DERNIÈRE FERMETURE (brutale ou normale), sa raison Android
//      (mémoire / ANR / plantage natif…), la mémoire au moment de la mort et
//      la dernière action en cours ;
//    • puis le journal (400 dernières lignes), défilable HAUT/BAS et par pages ;
//    • boutons : Actualiser · Copier (presse-papiers, pour l'envoyer au
//      support depuis l'appli télécommande) · Effacer.
//  Style : uniquement TvTokens / TvDimens / TvFocusBuilder existants (mêmes
//  cartes et boutons que l'écran Réglages). Aucune nouvelle couleur.
// =========================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/l10n_extension.dart';

import '../../../core/blackbox/black_box.dart';
import '../core/tv_dimens.dart';
import '../core/tv_focusable.dart';
import '../core/tv_tokens.dart';

class TvBlackBoxScreen extends StatefulWidget {
  const TvBlackBoxScreen({super.key});

  @override
  State<TvBlackBoxScreen> createState() => _TvBlackBoxScreenState();
}

class _TvBlackBoxScreenState extends State<TvBlackBoxScreen> {
  List<String> _lines = const <String>[];
  bool _loading = true;
  bool _copied = false;
  final ScrollController _scroll = ScrollController();
  static const double _kRow = 24;

  @override
  void initState() {
    super.initState();
    BlackBox.instance.info('SCREEN', 'Boîte noire ouverte');
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final List<String> l = await BlackBox.instance.tail(max: 400);
    if (!mounted) return;
    setState(() {
      _lines = l;
      _loading = false;
    });
    // On ouvre en BAS (les lignes les plus récentes).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _copy() async {
    final BlackBoxLastExit? x = BlackBox.instance.lastExit;
    final String head = x == null ? '' : '${x.headline}\n${x.lastAction}\n\n';
    await Clipboard.setData(ClipboardData(text: head + _lines.join('\n')));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _clear() async {
    await BlackBox.instance.clear();
    await _load();
  }

  void _scrollBy(double px) {
    if (!_scroll.hasClients) return;
    final double target = (_scroll.offset + px)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _scrollBy(_kRow * 3);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (_scroll.hasClients && _scroll.offset <= 0) {
        return KeyEventResult.ignored; // remonte le focus vers les boutons
      }
      _scrollBy(-_kRow * 3);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.pageDown || k == LogicalKeyboardKey.channelDown) {
      _scrollBy(_kRow * 15);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.pageUp || k == LogicalKeyboardKey.channelUp) {
      _scrollBy(-_kRow * 15);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final BlackBoxLastExit? x = BlackBox.instance.lastExit;
    final bool brutal = x?.brutal ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(context.l10n.tvBlackBoxTitle,
            style: TextStyle(
                fontSize: TvDimens.displayM,
                fontWeight: FontWeight.w800,
                color: TvTokens.text)),
        const SizedBox(height: 6),
        Text(
          context.l10n.tvBlackBoxSubtitle(BlackBox.instance.appVersion),
          style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted),
        ),
        const SizedBox(height: 18),

        // ----- Carte « dernière fermeture » -----
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: TvTokens.card,
            borderRadius: BorderRadius.circular(TvDimens.cardRadius),
            border: Border.all(color: brutal ? TvTokens.live : TvTokens.lineSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                x == null
                    ? context.l10n.tvBlackBoxFirstRun
                    : _headline(context, x),
                style: TextStyle(
                    fontSize: TvDimens.title,
                    fontWeight: FontWeight.w700,
                    color: brutal ? TvTokens.live : TvTokens.text),
              ),
              if (x != null && x.at != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(context.l10n.tvBlackBoxWhen(_fmt(x.at!)),
                    style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted)),
              ],
              if (x != null && x.lastAction.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(context.l10n.tvBlackBoxLastAction(x.lastAction),
                    style: TextStyle(fontSize: TvDimens.body, color: TvTokens.muted)),
              ],
              if (x != null && x.nativeDescription.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(context.l10n.tvBlackBoxDetail(x.nativeDescription),
                    style: TextStyle(fontSize: TvDimens.label, color: TvTokens.mutedDim)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ----- Boutons -----
        Row(
          children: <Widget>[
            _Btn(icon: Icons.refresh_rounded, label: context.l10n.tvRefresh, autofocus: true, onSelect: _load),
            const SizedBox(width: 12),
            _Btn(
                icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                label: _copied ? context.l10n.tvCopied : context.l10n.tvCopy,
                onSelect: _copy),
            const SizedBox(width: 12),
            _Btn(icon: Icons.delete_outline_rounded, label: context.l10n.tvClear, onSelect: _clear),
          ],
        ),
        const SizedBox(height: 14),

        // ----- Journal -----
        Expanded(
          child: Focus(
            onKeyEvent: _onKey,
            child: Builder(builder: (BuildContext context) {
              final bool focused = Focus.of(context).hasFocus;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: TvTokens.card.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(TvDimens.cardRadius),
                  border: Border.all(
                      color: focused ? TvTokens.accent : TvTokens.lineSoft),
                ),
                child: _loading
                    ? Center(
                        child: Text(context.l10n.tvReading,
                            style: TextStyle(
                                fontSize: TvDimens.body, color: TvTokens.mutedDim)))
                    : ListView.builder(
                        controller: _scroll,
                        itemExtent: _kRow,
                        itemCount: _lines.length,
                        itemBuilder: (BuildContext context, int i) {
                          final String l = _lines[i];
                          final Color c = l.contains(' F [')
                              ? TvTokens.live
                              : l.contains(' E [')
                                  ? TvTokens.live
                                  : l.contains(' W [')
                                      ? TvTokens.accentBright
                                      : TvTokens.muted;
                          return Text(l,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TvTokens.mono(13,
                                  weight: FontWeight.w400, color: c));
                        },
                      ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        Text(context.l10n.tvBlackBoxHelp,
            style: TextStyle(fontSize: TvDimens.label, color: TvTokens.mutedDim)),
      ],
    );
  }

  /// Titre de la carte « dernière fermeture », traduit (la boîte noire elle-
  /// même ne connaît pas la langue : elle expose des données, l'écran formate).
  String _headline(BuildContext context, BlackBoxLastExit x) {
    if (!x.brutal) return context.l10n.tvBlackBoxCleanExit;
    final String r = x.nativeReason.isEmpty
        ? context.l10n.tvBlackBoxUnknownReason
        : x.nativeReason;
    final String mem =
        x.pssMb > 0 ? ' · ${context.l10n.tvBlackBoxMemory(x.pssMb.toString())}' : '';
    return context.l10n.tvBlackBoxBrutal('$r$mem');
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}

/// Bouton pilule identique à ceux de l'écran Réglages.
class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.label,
    required this.onSelect,
    this.autofocus = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusBuilder(
      autofocus: autofocus,
      scale: TvFocusScale.large,
      onSelect: onSelect,
      builder: (BuildContext context, bool focused) {
        final Color bg = focused ? TvTokens.accent : TvTokens.sel;
        final Color fg = focused ? TvTokens.onAccent : TvTokens.accentBright;
        return Container(
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(TvDimens.cardRadius)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: fg, size: 24),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      fontSize: TvDimens.title,
                      fontWeight: FontWeight.w700,
                      color: fg)),
            ],
          ),
        );
      },
    );
  }
}
