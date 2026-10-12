// Identité privée dédiée au chat. Ni MAC publique ni jeton du panel :
// ce secret n'autorise QUE la conversation du téléphone et reste local.
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../device/data/device_identity.dart';
import '../../subscription/data/subscription_backend.dart';

class SupportMessage {
  const SupportMessage({
    required this.seq,
    required this.sender,
    required this.body,
    required this.createdAt,
  });
  final int seq;
  final String sender;
  final String body;
  final int createdAt;
  factory SupportMessage.fromJson(Map<String, dynamic> json) => SupportMessage(
    seq: (json['seq'] as num).toInt(),
    sender: json['sender'] as String,
    body: json['body'] as String,
    createdAt: (json['created_at'] as num).toInt(),
  );
}

class SupportPage {
  const SupportPage({
    required this.items,
    required this.more,
    required this.ownerRead,
    required this.unread,
  });
  final List<SupportMessage> items;
  final bool more;
  final int ownerRead;
  final int unread;
  factory SupportPage.fromJson(Map<String, dynamic> json) => SupportPage(
    items: (json['items'] as List<dynamic>? ?? <dynamic>[])
        .map((dynamic v) => SupportMessage.fromJson(v as Map<String, dynamic>))
        .toList(),
    more: json['more'] == true,
    ownerRead: (json['owner_read_seq'] as num?)?.toInt() ?? 0,
    unread: (json['unread'] as num?)?.toInt() ?? 0,
  );
}

class SupportRepository {
  SupportRepository({http.Client? client}) : _client = client ?? http.Client();
  static final SupportRepository instance = SupportRepository();
  final http.Client _client;
  Future<({String token, String id})>? _identity;
  static String newMessageId() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final String s = bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  Future<({String token, String id})> _loadIdentity() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('support.private.token.v1');
    if (token == null) {
      final Random r = Random.secure();
      token = base64UrlEncode(List<int>.generate(32, (_) => r.nextInt(256)))
          .replaceAll('=', '');
      if (!await prefs.setString('support.private.token.v1', token))
        throw StateError('Identité du chat indisponible.');
    }
    final Hash digest = await Sha256().hash(utf8.encode(token));
    return (
      token: token,
      id: digest.bytes
          .map((int b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
    );
  }

  Future<Map<String, dynamic>> _request(
    String method, {
    Map<String, Object>? body,
    String query = '',
  }) async {
    _identity ??= _loadIdentity();
    final ({String token, String id}) identity;
    try {
      identity = await _identity!;
    } catch (_) {
      _identity = null;
      rethrow;
    }
    final Uri uri = Uri.parse(
      '$kSubscriptionBaseUrl/api/support/${identity.id}$query',
    );
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Support-Token': identity.token,
    };
    final http.Response response;
    try {
      response =
          await (method == 'POST'
                  ? _client.post(uri, headers: headers, body: jsonEncode(body))
                  : method == 'PATCH'
                  ? _client.patch(uri, headers: headers, body: jsonEncode(body))
                  : _client.get(uri, headers: headers))
              .timeout(const Duration(seconds: 8));
    } catch (_) {
      throw StateError(
        'Connexion interrompue. Ton message reste prêt à envoyer.',
      );
    }
    if (response.statusCode == 429)
      throw StateError('Patiente une minute avant de réessayer.');
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw StateError('Le chat est momentanément indisponible. Réessaie.');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<SupportPage> messages({int? before}) async => SupportPage.fromJson(
    await _request('GET', query: before == null ? '' : '?before=$before'),
  );
  Future<int> unread() async =>
      ((await _request('GET', query: '?summary=1'))['unread'] as num?)
          ?.toInt() ??
      0;
  Future<void> read(int through) async {
    await _request('PATCH', body: <String, Object>{'read_through': through});
  }

  Future<void> send(String message, String id) async {
    final String mac = await DeviceIdentity.instance.mac;
    await _request(
      'POST',
      body: <String, Object>{
        'body': message.trim(),
        'client_id': id,
        'device_label': mac,
      },
    );
  }
}
