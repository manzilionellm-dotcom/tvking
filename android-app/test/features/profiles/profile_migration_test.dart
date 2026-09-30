// =========================================================
//  profile_migration_test.dart — Profils familiaux
// =========================================================
//  On vérifie la promesse de la mise à jour :
//    • sans catalogue, il n'y a que « Profil 1 » ;
//    • ses clés disque sont les ANCIENNES clés (rien à copier,
//      rien à effacer) ;
//    • favoris et historique historiques sont AJOUTÉS au profil 1,
//      jamais retirés, et les autres profils ne sont pas touchés ;
//    • on ne recopie pas une deuxième fois ;
//    • 4 profils max, un seul Enfants, le profil 1 ne se supprime pas ;
//    • le choix au démarrage ne s'affiche pas s'il n'y a rien à choisir
//      ou s'il est désactivé ;
//    • le profil Enfants ne peut pas couper le mode enfants ;
//    • une chaîne non classée n'est pas masquée « par précaution ».
// =========================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/features/profiles/domain/family_profile.dart';
import 'package:tv_king/features/profiles/domain/profile_catalog.dart';
import 'package:tv_king/features/profiles/domain/profile_migration.dart';
import 'package:tv_king/features/profiles/domain/profile_policies.dart';
import 'package:tv_king/features/profiles/domain/reminder_book.dart';

void main() {
  group('migration douce — le profil 1 EST les données d\'avant', () {
    test('catalogue vide → un seul Profil 1, choix non forcé', () {
      final ProfileCatalog c = ProfileCatalog.decode(null);
      expect(c.profiles, hasLength(1));
      expect(c.activeId, ProfileIds.origin);
      expect(c.active.name, 'Profil 1');
      expect(c.active.isKids, isFalse);
      expect(c.askOnStartup, isNull);
    });

    test('JSON cassé → Profil 1, sans exception', () {
      final ProfileCatalog c = ProfileCatalog.decode('{pas du json');
      expect(c.activeId, ProfileIds.origin);
      expect(c.profiles.single.id, ProfileIds.origin);
    });

    test('les clés du profil 1 sont les clés historiques', () {
      expect(ProfileKeys.watchProgress(ProfileIds.origin), 'cinema.progress.v1');
      expect(ProfileKeys.pin(ProfileIds.origin), 'security.app_pin_value');
      expect(ProfileKeys.kidsMode(ProfileIds.origin), 'security.kids_mode.v1');
      expect(ProfileKeys.reminders(ProfileIds.origin), 'notif.reminders.book.v1');
    });

    test('un autre profil n\'écrit pas dans les clés historiques', () {
      const String id = 'p99_0';
      expect(ProfileKeys.watchProgress(id), isNot('cinema.progress.v1'));
      expect(ProfileKeys.pin(id), isNot('security.app_pin_value'));
      expect(ProfileKeys.kidsMode(id), isNot('security.kids_mode.v1'));
      expect(ProfileKeys.watchProgress(id), 'cinema.progress.v1.$id');
    });

    test('supprimer un profil ne peut pas effacer les clés du profil 1', () {
      expect(ProfileKeys.disposableKeys(ProfileIds.origin), isEmpty);
      final List<String> gone = ProfileKeys.disposableKeys('p99_0');
      expect(gone, contains('cinema.progress.v1.p99_0'));
      expect(gone, isNot(contains('cinema.progress.v1')));
      expect(gone, isNot(contains('security.app_pin_value')));
    });

    test('favoris historiques ajoutés au profil 1, rien n\'est retiré', () {
      final Map<String, Set<String>> merged = ProfileMigration.mergeFavorites(
        legacyIds: <String>['tf1', 'm6', ''],
        scoped: <String, Set<String>>{
          ProfileIds.origin: <String>{'arte', 'tf1'},
          'p99_0': <String>{'cartoon'},
        },
      );
      expect(merged[ProfileIds.origin], <String>{'tf1', 'm6', 'arte'});
      expect(merged['p99_0'], <String>{'cartoon'});
    });

    test('historique : le tiroir du profil 1 gagne s\'il a déjà la chaîne', () {
      final Map<String, Map<String, int>> merged = ProfileMigration.mergeHistory(
        legacy: <String, int>{'tf1': 1, 'm6': 2, '': 9},
        scoped: <String, Map<String, int>>{
          ProfileIds.origin: <String, int>{'tf1': 50},
          'p99_0': <String, int>{'cartoon': 7},
        },
      );
      expect(merged[ProfileIds.origin]!['tf1'], 50);
      expect(merged[ProfileIds.origin]!['m6'], 2);
      expect(merged[ProfileIds.origin]!.containsKey(''), isFalse);
      expect(merged['p99_0']!['cartoon'], 7);
    });

    test('la copie ne se rejoue pas (un favori retiré ne revient pas)', () {
      expect(ProfileMigration.shouldCopyLegacy(alreadyMigrated: false), isTrue);
      expect(ProfileMigration.shouldCopyLegacy(alreadyMigrated: true), isFalse);
    });

    test('un catalogue sans profil 1 le rajoute et garde les autres', () {
      const String raw = '''
      {"activeId":"p9_0","profiles":[
        {"id":"p9_0","name":"Papa","avatar":1,"isKids":false,"createdAt":3}
      ]}''';
      final ProfileCatalog c = ProfileCatalog.decode(raw);
      expect(c.byId(ProfileIds.origin), isNotNull);
      expect(c.byId('p9_0')!.name, 'Papa');
      expect(c.activeId, 'p9_0');
    });

    test('aller-retour JSON : le choix désactivé reste désactivé', () {
      final ProfileCatalog c = ProfileCatalog.fresh().withAsk(false);
      final ProfileCatalog back = ProfileCatalog.decode(c.encode());
      expect(back.askOnStartup, isFalse);
      expect(back.active.name, 'Profil 1');
    });
  });

  group('règles des profils', () {
    test('4 maximum, un seul Enfants, profil 1 indestructible', () {
      ProfileCatalog c = ProfileCatalog.fresh(nowMs: 1);
      c = c.add(name: 'Papa', isKids: false, nowMs: 2)!;
      c = c.add(name: 'Maman', isKids: false, nowMs: 3)!;
      c = c.add(name: 'Enfants', isKids: true, nowMs: 4)!;
      expect(c.profiles, hasLength(4));
      expect(c.add(name: 'Invité', isKids: false, nowMs: 5), isNull);
      expect(c.add(name: 'Encore', isKids: true, nowMs: 6), isNull);
      expect(c.remove(ProfileIds.origin), isNull);
      final ProfileCatalog? withoutKids =
          c.remove(c.profiles.last.id);
      expect(withoutKids, isNotNull);
      expect(withoutKids!.hasKids, isFalse);
      expect(withoutKids.byId(ProfileIds.origin), isNotNull);
    });

    test('retirer le profil actif ramène au profil 1', () {
      ProfileCatalog c = ProfileCatalog.fresh(nowMs: 1);
      c = c.add(name: 'Papa', isKids: false, nowMs: 2)!;
      final String papa = c.profiles.last.id;
      c = c.activate(papa)!;
      c = c.remove(papa)!;
      expect(c.activeId, ProfileIds.origin);
    });

    test('nom vide refusé, nom trop long refusé', () {
      final ProfileCatalog c = ProfileCatalog.fresh();
      expect(c.add(name: '   ', isKids: false, nowMs: 1), isNull);
      expect(c.add(name: 'abcdefghijklmnopqrstuvwxyz', isKids: false, nowMs: 1), isNull);
      expect(c.rename(ProfileIds.origin, ''), isNull);
    });

    test('plus de 4 lignes au disque : on garde le profil 1', () {
      const String raw = '''
      {"activeId":"p5","profiles":[
        {"id":"p2","name":"A","avatar":0,"isKids":false,"createdAt":1},
        {"id":"p3","name":"B","avatar":0,"isKids":false,"createdAt":1},
        {"id":"p4","name":"C","avatar":0,"isKids":false,"createdAt":1},
        {"id":"p5","name":"D","avatar":0,"isKids":false,"createdAt":1},
        {"id":"p6","name":"E","avatar":0,"isKids":true,"createdAt":1}
      ]}''';
      final ProfileCatalog c = ProfileCatalog.decode(raw);
      expect(c.profiles, hasLength(4));
      expect(c.byId(ProfileIds.origin), isNotNull);
    });
  });

  group('démarrage et profil Enfants', () {
    test('pas de choix s\'il n\'y a qu\'un profil, ou si c\'est coupé', () {
      expect(
        StartupProfilePolicy.shouldOffer(askOnStartup: null, profileCount: 1),
        isFalse,
      );
      expect(
        StartupProfilePolicy.shouldOffer(askOnStartup: true, profileCount: 1),
        isFalse,
      );
      expect(
        StartupProfilePolicy.shouldOffer(askOnStartup: null, profileCount: 2),
        isTrue,
      );
      expect(
        StartupProfilePolicy.shouldOffer(askOnStartup: false, profileCount: 3),
        isFalse,
      );
      expect(
        StartupProfilePolicy.shouldOffer(askOnStartup: true, profileCount: 2),
        isTrue,
      );
    });

    test('le profil Enfants force le mode et ne se coupe pas', () {
      expect(
        KidsProfilePolicy.effectiveKidsMode(isKidsProfile: true, stored: false),
        isTrue,
      );
      expect(
        KidsProfilePolicy.effectiveKidsMode(isKidsProfile: false, stored: false),
        isFalse,
      );
      expect(
        KidsProfilePolicy.effectiveKidsMode(isKidsProfile: false, stored: true),
        isTrue,
      );
      expect(KidsProfilePolicy.canDisableKidsMode(isKidsProfile: true), isFalse);
      expect(KidsProfilePolicy.canDisableKidsMode(isKidsProfile: false), isTrue);
      expect(
        KidsProfilePolicy.mustConfirmLeave(
          currentIsKids: true,
          currentId: 'kids',
          nextId: ProfileIds.origin,
        ),
        isTrue,
      );
      expect(
        KidsProfilePolicy.mustConfirmLeave(
          currentIsKids: false,
          currentId: ProfileIds.origin,
          nextId: 'kids',
        ),
        isFalse,
      );
    });

    test('la recherche enfant ne bloque pas une chaîne normale', () {
      expect(
        KidsContentPolicy.hideFromKids(
          kidsMode: true,
          cachedIsAdult: null,
          name: 'TF1',
          category: 'France',
        ),
        isFalse,
      );
      expect(
        KidsContentPolicy.hideFromKids(
          kidsMode: true,
          cachedIsAdult: false,
          name: 'XXX',
          category: 'Adulte',
        ),
        isFalse,
      );
      expect(
        KidsContentPolicy.hideFromKids(
          kidsMode: true,
          cachedIsAdult: true,
          name: 'Chaîne',
          category: 'Divers',
        ),
        isTrue,
      );
      expect(
        KidsContentPolicy.hideFromKids(
          kidsMode: false,
          cachedIsAdult: true,
          name: 'XXX',
          category: 'Adulte',
        ),
        isFalse,
      );
      expect(KidsContentPolicy.looksAdult('TF1 HD'), isFalse);
      expect(KidsContentPolicy.looksAdult('Canal 2018+'), isFalse);
      expect(KidsContentPolicy.looksAdult('Dorcel TV'), isTrue);
      expect(KidsContentPolicy.looksAdult('Night 18+'), isTrue);
    });
  });

  group('rappels séparés', () {
    test('carnet : aller-retour, remplacement, oubli du passé', () {
      const ProgramReminder a = ProgramReminder(
        channelId: 'tf1',
        channelName: 'TF1',
        title: 'Journal',
        startMs: 5000000,
        leadMinutes: 5,
      );
      const ProgramReminder b = ProgramReminder(
        channelId: 'tf1',
        channelName: 'TF1',
        title: 'Journal (2)',
        startMs: 5000000,
        leadMinutes: 10,
      );
      final ReminderBook book = const ReminderBook()
          .upsert(a, nowMs: 0)
          .upsert(b, nowMs: 0);
      expect(book.items, hasLength(1));
      expect(book.items.single.leadMinutes, 10);
      final ReminderBook back = ReminderBook.decode(book.encode());
      expect(back.items.single.title, 'Journal (2)');
      expect(ReminderBook.decode('{cassé').items, isEmpty);
      final ReminderBook later = back.upsert(
        const ProgramReminder(
          channelId: 'm6',
          channelName: 'M6',
          title: 'Film',
          startMs: 100,
          leadMinutes: 5,
        ),
        nowMs: 5200000,
      );
      expect(later.items.any((ProgramReminder e) => e.channelId == 'tf1'), isFalse);
    });

    test('deux profils, le même programme : deux alarmes distinctes et stables', () {
      final int a = reminderNotificationId(
        profileId: ProfileIds.origin,
        channelId: 'tf1',
        startMs: 42,
      );
      final int b = reminderNotificationId(
        profileId: 'p99_0',
        channelId: 'tf1',
        startMs: 42,
      );
      final int again = reminderNotificationId(
        profileId: ProfileIds.origin,
        channelId: 'tf1',
        startMs: 42,
      );
      expect(a, again);
      expect(a, isNot(b));
      expect(a, greaterThan(0));
    });
  });
}
