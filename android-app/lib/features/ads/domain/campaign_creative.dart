// Recette de présentation bornée et versionnée. Une ancienne app garde
// le texte ; un modèle inconnu ne lance jamais du code ou une WebView.
class CampaignCreative {
  const CampaignCreative({
    required this.template,
    required this.palette,
    required this.imageUrl,
    required this.badge,
    required this.motion,
    required this.durationSeconds,
  });
  final String template, palette, imageUrl, badge;
  final bool motion;
  final int durationSeconds;
  static CampaignCreative? parse(Object? raw) {
    if (raw is! Map<String, dynamic> || raw['version'] != 1) return null;
    if (!<String>['orbit', 'prism', 'spotlight'].contains(raw['template']) ||
        !<String>['ember', 'ice', 'gold'].contains(raw['palette']) ||
        !<String>['gentle', 'still'].contains(raw['motion']) ||
        !<int>[6, 8, 10].contains(raw['duration_seconds']))
      return null;
    final Object? badge = raw['badge'], image = raw['image_url'];
    if (badge is! String ||
        badge.length > 24 ||
        image is! String ||
        image.length > 300)
      return null;
    final Uri? uri = image.isEmpty ? null : Uri.tryParse(image);
    if (image.isNotEmpty &&
        (uri == null ||
            uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty))
      return null;
    return CampaignCreative(
      template: raw['template'] as String,
      palette: raw['palette'] as String,
      imageUrl: image,
      badge: badge,
      motion: raw['motion'] == 'gentle',
      durationSeconds: raw['duration_seconds'] as int,
    );
  }
}
