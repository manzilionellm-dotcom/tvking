# Zuno pour Windows 10 / 11 (x64)

Entrée : `lib/main_windows.dart`. Le build utilise le même backend et le
même contrat d'activation que Zuno TV : licence, sources, profils, favoris,
films, séries, annonces et canal temps réel du panel. Le panel reçoit le
modèle **Zuno Windows**. Le champ plateforme reste `tv`, seul contrat bureau
compatible avec le Worker existant ; les mises à jour Windows utilisent
leur propre manifeste et numéro de build, jamais celui de l'APK TV.

## Utilisation PC

- Démarrage en fenêtre centrée ; taille et maximisation mémorisées.
- Souris : clic, survol visible, molette. Clavier : Tab, flèches, Entrée.
- F11 / Alt+Entrée : plein écran. Échap : retour d'un écran.
- Ctrl+F : recherche (différée tant qu'un lecteur est occupé).
- Barre supérieure : retour, recherche, plein écran ; cachée en plein écran.
- Une seule instance par session Windows ; une seconde ouverture ramène
  la fenêtre déjà ouverte au premier plan.

## Corrections Windows

Le lecteur sérialise ses commandes libmpv, invalide les ouvertures dépassées
et attend l'appel natif en vol avant destruction. Un zap ne reprend plus la
langue ou le choix de sous-titres du film précédent. SQLite migre de
Documents vers AppData (disque local), en conservant la base originale et
ses fichiers WAL. L'installeur et le portable incluent le runtime Visual C++.

Le canal panel se reconnecte après un retour à l'application. Un ping
WebSocket détecte une prise morte après veille ou coupure réseau. Le numéro
d'un ordre n'est consommé qu'après application ; un échec redéclenche une
reconnexion et le rejeu. Si WebSocket est indisponible, le canal long puis
le sondage existant prennent le relais. La réception est immédiate sur une
prise active ; l'import des chaînes dépend toujours du fournisseur et du
volume de la liste. Aucune source ni licence client n'est changée pour tester.

## Construire et vérifier

Workflow : `.github/workflows/build-zuno-windows.yml`.
Il génère le runner, vérifie l'analyse ciblée et les tests Windows/panel,
compile le release x64, contrôle les DLL, démarre réellement Zuno sur le
runner Windows, puis produit `Zuno-Setup.exe` et `zuno-windows.zip`.
Les artefacts de branche sont disponibles sans remplacer la release client.
La publication de production conserve le gel et ses protections existantes.
Les installeurs de revue désactivent les mises à jour automatiques pour
éviter de revenir à une ancienne release cliente durant leur évaluation.

Contrôles manuels avant une diffusion à grande échelle : écran à 100/150/200 %,
veille/reprise, carte graphique Intel/AMD/NVIDIA, HLS/MPEG-TS/VOD autorisés,
pistes audio et sous-titres, source/activation envoyées par le panel,
installation puis mise à jour conservant favoris et identité. Les tests
automatiques ne certifient pas tous les pilotes GPU ou fournisseurs IPTV.
La signature Authenticode requiert un certificat d'éditeur ; celui-ci n'est
pas fourni par le dépôt.
