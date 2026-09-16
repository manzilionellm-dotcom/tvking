import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/net/iptv_cert_store.dart';

void main() {
  test('refuse nos hôtes', () {
    expect(IptvCertTrust.isOurBackend('app.7themotion.com'), isTrue);
    expect(IptvCertTrust.isOurBackend('tvking-admin.pages.dev'), isTrue);
    expect(IptvCertTrust.isOurBackend('panel.example.test'), isFalse);
  });
}
