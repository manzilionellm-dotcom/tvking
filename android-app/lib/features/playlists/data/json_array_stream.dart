// =========================================================
//  json_array_stream.dart — Lire un gros tableau JSON élément par élément
// =========================================================
//  Pourquoi ?
//  ----------
//  `jsonDecode` construit l'ARBRE COMPLET en mémoire avant de rendre la main :
//  pour la réponse `get_live_streams` d'un fournisseur Xtream (une catégorie
//  « ALL » ou le bouquet entier jusqu'à 10 Mo), cela fait des dizaines de
//  milliers de Map de ~15 clés, soit plusieurs fois la taille du JSON, alors
//  qu'on n'en garde que quelques champs. L'import par catégorie en lit
//  plusieurs à la fois : sur une box à 899 Mo, ces arbres s'additionnent.
//
//  Ici on parcourt les OCTETS une seule fois pour repérer les bornes de
//  chaque élément du tableau, puis on décode ce SEUL élément (une petite
//  Map), on le rend à l'appelant, et il redevient libre aussitôt. Le pic
//  mémoire n'est plus « tout l'arbre » mais « un élément ».
//
//  Règles (identiques au décodage complet d'avant) :
//    - entrée = un tableau JSON `[ ... ]` (BOM et espaces tolérés) ;
//    - chaque élément est décodé par le vrai décodeur JSON de dart:convert
//      (mêmes règles d'échappement, nombres, Unicode, UTF-8 « malformé »
//      toléré comme avant) ;
//    - JSON tronqué, élément invalide ou texte après `]` → FormatException.
//  Une entrée qui n'est PAS un tableau (ex. `{"data": [...]}`) n'est pas
//  traitée ici : [JsonArrayStream.isTopLevelArray] permet à l'appelant de
//  garder l'ancien chemin pour ces serveurs rares.
// =========================================================
import 'dart:convert';
import 'dart:typed_data';

abstract final class JsonArrayStream {
  static const int _space = 0x20, _tab = 0x09, _lf = 0x0A, _cr = 0x0D;
  static const int _quote = 0x22, _backslash = 0x5C, _comma = 0x2C;
  static const int _openArr = 0x5B, _closeArr = 0x5D;
  static const int _openObj = 0x7B, _closeObj = 0x7D;

  static final Converter<List<int>, Object?> _decoder =
      const Utf8Decoder(allowMalformed: true).fuse(const JsonDecoder());

  static bool _isSpace(int b) => b == _space || b == _tab || b == _lf || b == _cr;

  /// Position du premier octet utile (après BOM UTF-8 et espaces).
  static int _start(Uint8List bytes) {
    int i = 0;
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      i = 3;
    }
    while (i < bytes.length && _isSpace(bytes[i])) {
      i++;
    }
    return i;
  }

  /// Vrai si la réponse commence par `[` (après BOM et espaces).
  static bool isTopLevelArray(Uint8List bytes) {
    final int i = _start(bytes);
    return i < bytes.length && bytes[i] == _openArr;
  }

  /// Fin (exclusive) de la valeur JSON qui commence à [from] : objets et
  /// tableaux imbriqués, chaînes avec échappements. Lève si elle n'est pas
  /// terminée avant la fin des octets.
  static int _valueEnd(Uint8List bytes, int from) {
    final int first = bytes[from];
    if (first == _quote) {
      int i = from + 1;
      while (i < bytes.length) {
        final int b = bytes[i];
        if (b == _backslash) {
          i += 2;
          continue;
        }
        if (b == _quote) return i + 1;
        i++;
      }
      throw const FormatException('Chaîne JSON non terminée');
    }
    if (first == _openObj || first == _openArr) {
      int depth = 0;
      int i = from;
      while (i < bytes.length) {
        final int b = bytes[i];
        if (b == _quote) {
          i = _valueEnd(bytes, i);
          continue;
        }
        if (b == _openObj || b == _openArr) {
          depth++;
        } else if (b == _closeObj || b == _closeArr) {
          depth--;
          if (depth == 0) return i + 1;
        }
        i++;
      }
      throw const FormatException('Objet ou tableau JSON non terminé');
    }
    // Nombre, true, false, null : jusqu'au prochain séparateur.
    int i = from;
    while (i < bytes.length) {
      final int b = bytes[i];
      if (b == _comma || b == _closeArr || b == _closeObj || _isSpace(b)) break;
      i++;
    }
    return i;
  }

  /// Parcourt les éléments du tableau JSON de premier niveau, un à la fois.
  /// [FormatException] si l'entrée n'est pas un tableau JSON valide.
  static Iterable<Object?> elements(Uint8List bytes) sync* {
    for (final (int start, int end) in spans(bytes)) {
      // Le VRAI décodeur JSON valide et décode cet élément seulement.
      yield _decoder.convert(Uint8List.sublistView(bytes, start, end));
    }
  }

  /// Bornes `[début, fin[` de chaque élément du tableau de premier niveau,
  /// SANS rien décoder. Même contrôle de structure que [elements].
  static Iterable<(int, int)> spans(Uint8List bytes) sync* {
    int i = _start(bytes);
    if (i >= bytes.length || bytes[i] != _openArr) {
      throw const FormatException('Tableau JSON attendu');
    }
    i++;
    bool expectValue = true;
    bool first = true;
    while (true) {
      while (i < bytes.length && _isSpace(bytes[i])) {
        i++;
      }
      if (i >= bytes.length) {
        throw const FormatException('Tableau JSON non terminé');
      }
      final int b = bytes[i];
      if (b == _closeArr) {
        // `[]` ou dernier élément. Une virgule finale `[1,]` est refusée,
        // comme par jsonDecode.
        if (expectValue && !first) {
          throw const FormatException('Virgule finale dans le tableau JSON');
        }
        i++;
        break;
      }
      if (!expectValue) {
        if (b != _comma) {
          throw const FormatException('Virgule attendue entre deux éléments');
        }
        i++;
        expectValue = true;
        continue;
      }
      final int end = _valueEnd(bytes, i);
      yield (i, end);
      i = end;
      expectValue = false;
      first = false;
    }
    while (i < bytes.length && _isSpace(bytes[i])) {
      i++;
    }
    if (i != bytes.length) {
      throw const FormatException('Contenu inattendu après le tableau JSON');
    }
  }

  /// Décode complètement l'élément `[start, end[` (vrai décodeur JSON).
  static Object? decode(Uint8List bytes, int start, int end) =>
      _decoder.convert(Uint8List.sublistView(bytes, start, end));

  /// Vrai si l'élément `[start, end[` est un objet JSON (`{...}`).
  static bool isObject(Uint8List bytes, int start) =>
      start < bytes.length && bytes[start] == _openObj;

  /// Lit dans l'objet JSON `[start, end[` UNIQUEMENT les clés de [wanted]
  /// et rend leur valeur décodée (String, int, double, bool, null, ou Map /
  /// List si la valeur est composée). Les autres valeurs sont SAUTÉES sans
  /// rien allouer. Une clé répétée garde sa dernière valeur, comme une Map
  /// décodée. Valeurs rendues = exactement celles de `jsonDecode`.
  ///
  /// Les valeurs des clés NON demandées ne sont pas validées en détail
  /// (seulement leur structure) : un champ inutile mal formé ne fait plus
  /// échouer toute la catégorie.
  static Map<String, Object?> fields(
      Uint8List bytes, int start, int end, Set<String> wanted) {
    final Map<String, Object?> out = <String, Object?>{};
    if (!isObject(bytes, start)) {
      throw const FormatException('Objet JSON attendu');
    }
    int i = start + 1;
    bool first = true;
    while (true) {
      while (i < end && _isSpace(bytes[i])) {
        i++;
      }
      if (i >= end) throw const FormatException('Objet JSON non terminé');
      if (bytes[i] == _closeObj) {
        if (!first) throw const FormatException('Virgule finale dans un objet JSON');
        return out;
      }
      if (bytes[i] != _quote) throw const FormatException('Clé JSON attendue');
      final int keyEnd = _valueEnd(bytes, i);
      final String key = _string(bytes, i, keyEnd);
      i = keyEnd;
      while (i < end && _isSpace(bytes[i])) {
        i++;
      }
      if (i >= end || bytes[i] != 0x3A) throw const FormatException('« : » attendu');
      i++;
      while (i < end && _isSpace(bytes[i])) {
        i++;
      }
      if (i >= end) throw const FormatException('Valeur JSON attendue');
      final int valueEnd = _valueEnd(bytes, i);
      if (valueEnd <= i) throw const FormatException('Valeur JSON vide');
      if (wanted.contains(key)) out[key] = _scalar(bytes, i, valueEnd);
      i = valueEnd;
      while (i < end && _isSpace(bytes[i])) {
        i++;
      }
      if (i >= end) throw const FormatException('Objet JSON non terminé');
      if (bytes[i] == _closeObj) return out;
      if (bytes[i] != _comma) throw const FormatException('Virgule attendue dans un objet JSON');
      i++;
      first = false;
      // Une virgule suivie de « } » est refusée, comme par jsonDecode.
      while (i < end && _isSpace(bytes[i])) {
        i++;
      }
      if (i < end && bytes[i] == _closeObj) {
        throw const FormatException('Virgule finale dans un objet JSON');
      }
    }
  }

  /// Chaîne JSON `"..."` : chemin rapide sans échappement (UTF-8 direct, même
  /// remplacement des octets invalides que le décodeur fusionné), sinon le
  /// décodeur JSON officiel.
  static String _string(Uint8List bytes, int start, int end) {
    for (int k = start + 1; k < end - 1; k++) {
      if (bytes[k] == _backslash) {
        return _decoder.convert(Uint8List.sublistView(bytes, start, end))! as String;
      }
    }
    return const Utf8Decoder(allowMalformed: true).convert(bytes, start + 1, end - 1);
  }

  static Object? _scalar(Uint8List bytes, int start, int end) {
    final int b = bytes[start];
    if (b == _quote) return _string(bytes, start, end);
    // null / true / false / nombre / objet / tableau : décodeur officiel
    // (valeurs courtes, rares hors chaînes).
    return _decoder.convert(Uint8List.sublistView(bytes, start, end));
  }
}
