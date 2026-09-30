// =========================================================
//  remote_page.dart — Page web affichée par le téléphone
// =========================================================
//  Une seule page, sans rien à télécharger ailleurs (pas de
//  police, pas de script externe). Les boutons parlent à la
//  box, sur le même Wi-Fi. Le jeton est déjà dans l'adresse :
//  sans lui, la box ne sert pas la page.
// =========================================================

String remoteControlPage(String token) {
  final String safe = token.replaceAll(RegExp(r'[^a-fA-F0-9]'), '');
  return '''
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Zuno</title>
<style>
  body { margin: 0; background: #111; color: #fff;
         font-family: sans-serif; text-align: center; }
  h1 { font-weight: 600; letter-spacing: 0.08em; }
  button { font-size: 22px; margin: 8px; padding: 18px 22px;
           border: 0; border-radius: 14px; background: #e6c15a; color: #111; }
  p { color: #bbb; }
</style>
</head>
<body>
<h1>ZUNO</h1>
<p>Même Wi-Fi que la box. Ouvre une chaîne, puis utilise ces touches.</p>
<div>
  <button type="button" onclick="c('up')">Haut</button>
</div>
<div>
  <button type="button" onclick="c('left')">Gauche</button>
  <button type="button" onclick="c('ok')">OK</button>
  <button type="button" onclick="c('right')">Droite</button>
</div>
<div>
  <button type="button" onclick="c('down')">Bas</button>
</div>
<div>
  <button type="button" onclick="c('play')">Lecture</button>
  <button type="button" onclick="c('back')">Retour</button>
</div>
<script>
function c(name) {
  fetch('/cmd?t=$safe&c=' + name, { method: 'POST' }).catch(function () {});
}
</script>
</body>
</html>
''';
}
