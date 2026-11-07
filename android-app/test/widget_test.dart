import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/network/api_config.dart';

void main() {
  test('panel API uses one HTTPS origin, never the legacy panel host', () {
    final Uri uri = Uri.parse(kApiBaseUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, isNot('app.7themotion.com'));
    expect(uri.path, anyOf('', '/'));
    expect(kNoCacheHeaders['Cache-Control'], contains('no-store'));
  });
}
