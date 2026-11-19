// Sonde d'image, absente de tout APK client.
//
// Le workflow et les box n'envoient pas ZUNO_PLAYER_PROBE_URL. La constante
// est alors vide et l'accueil normal s'affiche. Un build d'essai local peut
// passer un flux public (Big Buck Bunny, etc.) pour vérifier que la
// SurfaceView montre vraiment des pixels, sans graver d'adresse dans le
// dépôt et sans toucher à l'activation ni à la MAC.

const String kZunoPlayerProbeUrl = String.fromEnvironment(
  'ZUNO_PLAYER_PROBE_URL',
);
