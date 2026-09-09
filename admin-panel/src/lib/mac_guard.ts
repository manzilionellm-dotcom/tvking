// =====================================================================
//  mac_guard.ts — « cette adresse MAC n'existe pas »
// =====================================================================
//  Demande du propriétaire (09/09/2026), mot pour mot : « si je me
//  trompe d'un chiffre, ça active quand même. Il faut me corriger : ça
//  doit me dire que l'adresse MAC n'existe pas. »
//
//  CE QUI SE PASSAIT. Le serveur créait l'appareil s'il n'existait pas.
//  Un seul caractère de travers et on posait une licence sur une MAC
//  FANTÔME : les crédits partaient, l'écran affichait « activé », et le
//  vrai client restait bloqué. Personne ne voyait rien avant son appel.
//
//  CE QUI SE PASSE MAINTENANT. Le serveur refuse (`mac_unknown`, 404) et
//  joint, quand il en trouve, les MAC connues qui ne diffèrent que d'UN
//  caractère — la correction probable. Ce fichier transforme ce refus en
//  question claire.
//
//  POURQUOI ON DEMANDE AU LIEU DE BLOQUER. La pré-activation est un vrai
//  usage : on vend AVANT que le client installe l'app, donc avant que sa
//  MAC existe. Bloquer sèchement casserait la vente. On demande donc une
//  confirmation explicite ; le serveur ne crée l'appareil que si elle
//  arrive (`allow_new: true`).
//
//  UNE SEULE IMPLÉMENTATION, PLUSIEURS APPELANTS — même raison que
//  `cloudflare/device_profiles.js` ou `ci/build_label.sh`. Deux écrans
//  saisissent une MAC à la main (Activation, Familles) ; le jour où une
//  copie du texte dériverait, un des deux avertirait moins bien que
//  l'autre, et c'est celui-là qui laisserait passer la faute de frappe.
import { ApiError } from './api';

/// Vrai si l'erreur est bien « MAC jamais vue » et non autre chose
/// (401, plan interdit, crédits insuffisants…). Ces cas-là doivent
/// continuer de remonter tels quels : ils ne se confirment pas.
export function isUnknownMac(e: unknown): e is ApiError {
  return e instanceof ApiError && e.code === 'mac_unknown';
}

/// Affiche l'avertissement et renvoie le choix de l'humain :
///   `true`  → « active quand même » (pré-activation assumée)
///   `false` → « je corrige » (l'appelant s'arrête sans rien activer)
///
/// `e` est l'ApiError `mac_unknown` : elle transporte les suggestions
/// calculées par le serveur (`data.suggestions`).
export function confirmUnknownMac(mac: string, e: ApiError): boolean {
  const proches = (e.data?.suggestions as string[] | undefined) ?? [];
  // Le passage qui sauve vraiment la mise : montrer la MAC voisine.
  // Voir « MK:1A:2B:3C:4D:5E » juste sous « MK:1A:2B:3C:4D:6E » rend la
  // faute de frappe évidente en une seconde, là où un simple refus
  // laisserait l'opérateur relire dix fois le même numéro.
  const aide = proches.length
    ? `\n\n🔎 Adresse(s) très proche(s), déjà connue(s) :\n${proches.join('\n')}` +
      '\n\nSi c\'est l\'une d\'elles, corrige le numéro : sinon tu actives ' +
      'un appareil qui n\'existe pas, et les crédits sont dépensés pour rien.'
    : '\n\nAucun appareil n\'a jamais démarré l\'application avec ce numéro.';
  return window.confirm(
    `⚠️ CETTE ADRESSE MAC N'EXISTE PAS\n\n${mac}${aide}\n\n` +
    '• Annuler → corriger le numéro (recommandé)\n' +
    '• OK → activer quand même (pré-activation : le client n\'a pas ' +
    'encore installé l\'app)',
  );
}

/// Le message d'erreur affiché sur la page quand l'opérateur choisit de
/// corriger. Centralisé ici pour que les deux écrans disent la même chose.
export function unknownMacNotice(mac: string): string {
  return `Adresse MAC inconnue : ${mac}. Vérifie le numéro, rien n'a été activé.`;
}
