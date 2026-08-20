// =========================================================
//  source_preflight_classify_test.dart — la table de décision, verrouillée
// =========================================================
//  Chantier traductions (20/08) : humanize() renvoyait du français en dur,
//  affiché tel quel dans les 7 autres langues. L'UI passe désormais par
//  classify() (raison typée → l10n). Ces tests verrouillent la table de
//  classement — si un cas change de raison, un écran change de message.
// =========================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tv_king/features/playlists/data/playlist_import_limits.dart';
import 'package:tv_king/features/playlists/data/source_preflight.dart';
import 'package:tv_king/features/playlists/data/xtream_client.dart';

void main() {
  test('une SourcePreflightException porte sa raison telle quelle', () {
    final SourcePreflightException e = SourcePreflightException(
        SourcePreflightIssue.notAPlaylist, 'pas une liste');
    expect(SourcePreflight.classify(e), SourcePreflightIssue.notAPlaylist);
    // humanize laisse passer le message déjà formulé (journaux).
    expect(SourcePreflight.humanize(e), 'pas une liste');
  });

  test('erreurs réseau : timeout, TLS, DNS, port fermé, coupure', () {
    expect(SourcePreflight.classify(TimeoutException('t')),
        SourcePreflightIssue.timeout);
    expect(SourcePreflight.classify(const HandshakeException('tls')),
        SourcePreflightIssue.tlsFailed);
    expect(
        SourcePreflight.classify(
            const SocketException('Failed host lookup: serveur.com')),
        SourcePreflightIssue.hostNotFound);
    expect(
        SourcePreflight.classify(const SocketException('Connection refused')),
        SourcePreflightIssue.portRefused);
    expect(SourcePreflight.classify(http.ClientException('closed')),
        SourcePreflightIssue.connectionInterrupted);
  });

  test('erreurs Xtream : identifiants, compte inactif, pas un panel', () {
    expect(SourcePreflight.classify(XtreamException('Identifiants refusés')),
        SourcePreflightIssue.xtreamBadCredentials);
    expect(
        SourcePreflight.classify(XtreamException('Compte non-actif status=x')),
        SourcePreflightIssue.xtreamAccountInactive);
    expect(SourcePreflight.classify(XtreamException('réponse non-JSON')),
        SourcePreflightIssue.xtreamNotAPanel);
  });

  test('liste trop grosse et filet final', () {
    expect(SourcePreflight.classify(const PlaylistImportTooLarge('trop')),
        SourcePreflightIssue.listTooLarge);
    expect(SourcePreflight.classify(Exception('mystère total')),
        SourcePreflightIssue.generic);
    // La projection française du filet reste humaine (journaux) : jamais
    // de jargon technique.
    expect(SourcePreflight.humanize(Exception('mystère total')),
        contains('Connexion impossible'));
  });
}
