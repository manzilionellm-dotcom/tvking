import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../channels/domain/channel.dart';
import '../../profiles/data/active_profile.dart';
import '../core/tv_focusable.dart';
import '../core/tv_search_text.dart';
import '../core/tv_tokens.dart';
import '../data/vip_countries_repository.dart';
import '../domain/vip_countries.dart';
import 'tv_components.dart';
import 'vip_country_names.dart';

/// Éditeur sans lecture vidéo : OK ajoute/retire, flèches pour l'ordre,
/// Enregistrer valide tout. Retour abandonne les changements non enregistrés.
class TvVipCountriesScreen extends StatefulWidget {
  const TvVipCountriesScreen({super.key, required this.available});
  final Map<String, int> available;

  @override
  State<TvVipCountriesScreen> createState() => _TvVipCountriesScreenState();
}

class _TvVipCountriesScreenState extends State<TvVipCountriesScreen> {
  late final String _profileId = ActiveProfile.instance.id;
  late List<String> _selected = VipCountriesRepository.instance.current
      .toList();
  String _query = '';
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    ActiveProfile.instance.listenable.addListener(_profileChanged);
  }

  void _profileChanged() {
    // Un éditeur ouvert pour un autre profil est fermé, jamais réaffecté.
    if (mounted && ActiveProfile.instance.id != _profileId)
      Navigator.of(context).pop();
  }

  @override
  void dispose() {
    ActiveProfile.instance.listenable.removeListener(_profileChanged);
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || ActiveProfile.instance.id != _profileId) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await VipCountriesRepository.instance.save(
        _selected,
        profileId: _profileId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _failed = true;
        });
    }
  }

  void _toggle(String code) {
    setState(() {
      if (_selected.contains(code)) {
        _selected.remove(code);
      } else if (_selected.length < VipCountries.limit) {
        _selected.add(code);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final codes =
        {...widget.available.keys, ..._selected}.where((code) {
          final country = ChannelClassifier.countryForKey(code);
          return country != null &&
              (tvSearchKey(
                    '${vipCountryName(l, code)} ${country.name} ${country.code}',
                  ).contains(tvSearchKey(_query)) ||
                  ChannelClassifier.detectCountryKey('', _query) == code);
        }).toList()..sort(
          (a, b) => vipCountryName(l, a).compareTo(vipCountryName(l, b)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.vipCountriesTitle,
                style: TvTokens.ui(28, weight: FontWeight.w700),
              ),
            ),
            Text(
              '${_selected.length} / ${VipCountries.limit}',
              style: TvTokens.ui(20, color: TvTokens.accentBright),
            ),
            const SizedBox(width: 24),
            TvCtaButton(
              label: l.buttonSave,
              onSelect: _saving ? null : _save,
              expand: false,
            ),
            const SizedBox(width: 16),
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: Text(l.buttonCancel),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l.vipCountriesHint, style: TvTokens.ui(17, color: TvTokens.muted)),
        if (_failed)
          Text(
            l.vipCountriesSaveError,
            style: TvTokens.ui(17, color: TvTokens.accentBright),
          ),
        const SizedBox(height: 20),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: l.navSearch,
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: codes.isEmpty
                          ? Center(
                              child: Text(
                                l.vipCountriesEmpty,
                                style: TvTokens.ui(18),
                              ),
                            )
                          : ListView.builder(
                              itemCount: codes.length,
                              itemBuilder: (context, index) {
                                final code = codes[index];
                                final selected = _selected.contains(code);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: TvFocusable(
                                    key: ValueKey('vip-add-$code'),
                                    autofocus: index == 0,
                                    enabled:
                                        !_saving &&
                                        (selected ||
                                            _selected.length <
                                                VipCountries.limit),
                                    selected: selected,
                                    scale: TvFocusScale.none,
                                    onSelect: () => _toggle(code),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          VipCountryFlag(code: code),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              vipCountryName(l, code),
                                              style: TvTokens.ui(20),
                                            ),
                                          ),
                                          Text(
                                            '${widget.available[code] ?? 0}',
                                            style: TvTokens.ui(
                                              17,
                                              color: TvTokens.muted,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Icon(
                                            selected
                                                ? Icons.check_circle
                                                : Icons.add_circle_outline,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.vipCountriesOrder,
                      style: TvTokens.ui(20, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _selected.length,
                        itemBuilder: (context, index) {
                          final code = _selected[index];
                          return Padding(
                            key: ValueKey('vip-order-$code'),
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Text(
                                  '${index + 1}',
                                  style: TvTokens.ui(
                                    20,
                                    color: TvTokens.accentBright,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                VipCountryFlag(code: code),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    vipCountryName(l, code),
                                    style: TvTokens.ui(18),
                                  ),
                                ),
                                _orderButton(
                                  Icons.arrow_upward,
                                  l.vipCountriesMoveUp,
                                  index > 0 && !_saving
                                      ? () => setState(
                                          () => _selected = VipCountries.move(
                                            _selected,
                                            index,
                                            index - 1,
                                          ).toList(),
                                        )
                                      : null,
                                ),
                                _orderButton(
                                  Icons.arrow_downward,
                                  l.vipCountriesMoveDown,
                                  index + 1 < _selected.length && !_saving
                                      ? () => setState(
                                          () => _selected = VipCountries.move(
                                            _selected,
                                            index,
                                            index + 1,
                                          ).toList(),
                                        )
                                      : null,
                                ),
                                _orderButton(
                                  Icons.close,
                                  l.vipCountriesRemove,
                                  !_saving ? () => _toggle(code) : null,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _orderButton(IconData icon, String label, VoidCallback? action) =>
      Tooltip(
        message: label,
        child: Semantics(
          label: label,
          button: true,
          child: TvFocusable(
            enabled: action != null,
            onSelect: action,
            scale: TvFocusScale.none,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                icon,
                color: action == null ? TvTokens.mutedDim : TvTokens.text,
              ),
            ),
          ),
        ),
      );
}

/// Image de drapeau avec repli lisible hors ligne (pas de carré emoji vide).
class VipCountryFlag extends StatelessWidget {
  const VipCountryFlag({super.key, required this.code});
  final String code;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 28,
    child: CachedNetworkImage(
      imageUrl: 'https://flagcdn.com/w80/${code == 'uk' ? 'gb' : code}.png',
      fit: BoxFit.contain,
      placeholder: (context, url) =>
          Center(child: Text(code.toUpperCase(), style: TvTokens.ui(14))),
      errorWidget: (context, url, error) =>
          Center(child: Text(code.toUpperCase(), style: TvTokens.ui(14))),
    ),
  );
}
