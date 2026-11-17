import '../../../core/blackbox/black_box_redaction.dart';
import '../../channels/domain/channel.dart';

// Les variantes (RAW, UHD, etc.) font partie du nom donné par le fournisseur.
// Une adresse ou un identifiant glissés dans le nom ne doivent jamais être
// affichés. Le nom contrôlé suit la durée de vie de la chaîne en mémoire.
final _names = Expando<String>();
final _controls = RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]');

String tvProviderChannelName(Channel channel, String fallback) {
  final String? cached = _names[channel];
  if (cached != null) return cached.isEmpty ? fallback : cached;
  final String label = channel.name.replaceAll(_controls, ' ').trim();
  final String safe = redactBlackBox(label) == label ? label : '';
  _names[channel] = safe;
  return safe.isEmpty ? fallback : safe;
}
