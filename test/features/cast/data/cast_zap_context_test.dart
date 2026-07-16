// =========================================================
//  cast_zap_context_test.dart — VAGUE B : télécommande pure
// =========================================================
//  Le client l'exige : pendant un cast, le téléphone est une
//  TÉLÉCOMMANDE. Zapper change la chaîne SUR LA TV, jamais en
//  local. Pour ça, le CastManager porte un « contexte de zap »
//  (playlist + index) partagé par toutes les surfaces (lecteur,
//  overlay, mini-barre).
//
//  Ces tests verrouillent les invariants du contexte de zap :
//    1. castChannelOnCurrentSession SANS session/cible → false,
//       et AUCUN effet de bord (pas d'état modifié) ;
//    2. setCastPlaylist mémorise playlist + index de la chaîne
//       courante (currentCastChannel) ;
//    3. canZapOnCast reste false hors cast, même avec playlist
//       (les boutons Ch+/Ch- des surfaces globales se masquent) ;
//    4. zapCastNext/Prev hors cast = no-op silencieux (jamais de
//       requête réseau ni de crash depuis un bouton).
//
//  Si un patch futur casse un de ces invariants, le zapping
//  télécommande redeviendrait un zapping local (2 connexions sur
//  les comptes 1-connexion) — on saute ici.
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/cast/data/cast_manager.dart';
import 'package:tv_king/features/channels/domain/channel.dart';

Channel _chan(int n) => Channel(
      id: 'zap-$n',
      name: 'Chaîne $n',
      category: 'TNT',
      streamUrl: 'http://panel.example/live/U/P/$n.ts',
      isLive: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final CastManager mgr = CastManager.instance;
  final List<Channel> playlist = List<Channel>.generate(4, (int i) => _chan(i));

  test(
      'castChannelOnCurrentSession sans session ni cible → false, '
      'sans effet de bord', () async {
    // Aucun device actif ni mémorisé dans un environnement de test.
    final bool ok = await mgr.castChannelOnCurrentSession(
      streamUrl: 'http://panel.example/live/U/P/1.ts',
      title: 'Chaîne 1',
    );
    expect(ok, isFalse,
        reason: 'sans _device ni _selectedDevice, le swap doit refuser '
            'proprement (l\'appelant décide, sans crash)');
    expect(mgr.state, CastState.idle,
        reason: 'un refus de swap ne doit PAS toucher l\'état de session');
  });

  test('setCastPlaylist mémorise playlist + index de la chaîne courante',
      () {
    mgr.setCastPlaylist(playlist, playlist[2]);
    expect(mgr.currentCastChannel?.id, 'zap-2',
        reason: 'l\'index doit pointer la chaîne qui vient de partir '
            'vers la TV');
  });

  test('canZapOnCast reste false hors cast, même avec une playlist', () {
    mgr.setCastPlaylist(playlist, playlist.first);
    expect(mgr.isCasting, isFalse, reason: 'pré-condition : pas de cast');
    expect(mgr.canZapOnCast, isFalse,
        reason: 'les Ch+/Ch- globaux ne doivent apparaître QUE pendant '
            'un cast actif');
  });

  test('zapCastNext / zapCastPrev hors cast = no-op silencieux', () async {
    mgr.setCastPlaylist(playlist, playlist[1]);
    // Hors cast : aucun réseau ne doit partir, l'index ne bouge pas.
    await mgr.zapCastNext();
    await mgr.zapCastPrev();
    expect(mgr.currentCastChannel?.id, 'zap-1',
        reason: 'hors cast, le zap télécommande ne doit RIEN faire '
            '(ni réseau, ni déplacement d\'index)');
    expect(mgr.state, CastState.idle);
  });
}
