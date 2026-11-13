import 'package:flutter/widgets.dart';

import '../../../core/i18n/l10n_extension.dart';
import '../../profiles/domain/family_profile.dart';
import 'tv_localized_format.dart';

/// Le profil créé automatiquement ne doit pas imposer un nom français.
/// Présentation seulement : les identifiants, données et noms personnalisés
/// restent inchangés dans le catalogue partagé.
String tvProfileLabel(BuildContext context, FamilyProfile profile) =>
    profile.id == ProfileIds.origin && profile.name == 'Profil 1'
    ? '${context.l10n.navProfile} ${tvNumber(context, 1)}'
    : profile.name;
