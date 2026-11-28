import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_king/core/app/novatube_tv_edition.dart';
import 'package:tv_king/features/tv/presentation/tv_hub_screen.dart';

void main() {
  test('le tunnel Android est visible seul et sur son réseau sous-jacent', () {
    for (final transport in [
      ConnectivityResult.wifi,
      ConnectivityResult.ethernet,
      ConnectivityResult.mobile,
    ]) {
      final base = tvConnectionIcon([transport]);
      expect(base, isNot(Icons.wifi_off_rounded));
      expect(tvConnectionIcon([transport, ConnectivityResult.vpn]),
          kNovatubeTv ? Icons.vpn_lock_rounded : base);
    }
    expect(tvConnectionIcon([ConnectivityResult.vpn]),
        kNovatubeTv ? Icons.vpn_lock_rounded : Icons.wifi_off_rounded);
    expect(tvConnectionIcon([ConnectivityResult.none]), Icons.wifi_off_rounded);
  });
}
