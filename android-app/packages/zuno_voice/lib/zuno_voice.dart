// =========================================================
//  zuno_voice.dart — nom du canal natif
// =========================================================
//  Le code utile est en Kotlin (android/). Ce fichier existe pour
//  que l'app Dart parle au MÊME canal, et pour documenter le contrat.
//
//  Méthodes (Dart → Android) :
//    listen()       → {status, text?}   status = ok | empty | unavailable
//                                        | cancelled | failed | busy
//    takePending()  → String?   phrase déjà reçue par le micro système
//
//  Appel (Android → Dart) :
//    onVoiceQuery(String)   la télécommande a envoyé une recherche
// =========================================================

/// Canal MethodChannel. Doit être le même côté Kotlin.
const String kZunoVoiceChannel = 'com.manzilionellm.zuno/voice';
