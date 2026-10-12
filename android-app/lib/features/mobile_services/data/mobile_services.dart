// Services facultatifs, indépendants du canal panel. Les clés ci-dessous
// sont des clés SDK publiques : aucun secret serveur n'entre dans l'APK.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:growthbook_sdk_flutter/growthbook_sdk_flutter.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/data/support_repository.dart';

class MobileServices extends ChangeNotifier {
  MobileServices._();
  static final MobileServices instance = MobileServices._();
  static const String growthKey = String.fromEnvironment(
    'GROWTHBOOK_CLIENT_KEY',
  );
  static const String growthHost = String.fromEnvironment(
    'GROWTHBOOK_HOST',
    defaultValue: 'https://cdn.growthbook.io',
  );
  static const String posthogKey = String.fromEnvironment(
    'POSTHOG_PROJECT_KEY',
  );
  static const String posthogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://eu.i.posthog.com',
  );
  bool wifiDownloads = true;
  bool analyticsConsent = false;
  bool visualMotion = true;
  Future<void>? _initializing;
  bool _analyticsReady = false;
  GrowthBookSDK? _growth;
  static bool httpsHost(String value) {
    final Uri? u = Uri.tryParse(value);
    return u != null &&
        u.scheme == 'https' &&
        u.host.isNotEmpty &&
        u.userInfo.isEmpty;
  }

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      wifiDownloads = p.getBool('mobile.wifi_downloads') ?? true;
      analyticsConsent = p.getBool('mobile.analytics_consent') ?? false;
      visualMotion = p.getBool('mobile.visual_motion') ?? true;
      notifyListeners();
      if (analyticsConsent) unawaited(_startAnalytics());
      unawaited(_startExperiments(p));
    } catch (_) {
      /* Une panne de service externe ne bloque pas l'app. */
    }
  }

  Future<void> _startExperiments(SharedPreferences p) async {
    try {
      if (growthKey.isNotEmpty && httpsHost(growthHost)) {
        final String id =
            p.getString('mobile.experiment_id') ??
            SupportRepository.newMessageId();
        await p.setString('mobile.experiment_id', id);
        _growth = await GBSDKBuilderApp(
          hostURL: growthHost,
          apiKey: growthKey,
          attributes: <String, dynamic>{
            'id': id,
            'platform': defaultTargetPlatform.name,
          },
          backgroundSync: false,
          growthBookTrackingCallBack: (_) {},
        ).initialize().timeout(const Duration(seconds: 8));
        // Le seul interrupteur distant concerne l'animation des pubs.
        // Activation, source, réseau et chat ne sont jamais pilotés ici.
        notifyListeners();
      }
    } catch (_) {
      /* La présentation reste disponible hors ligne. */
    }
  }

  bool get allowVisualMotion {
    if (!visualMotion) return false;
    final Object? value = _growth?.feature('motion_ads_3d').value;
    return value is bool ? value : true;
  }

  Future<void> setWifiDownloads(bool value) async {
    wifiDownloads = value;
    await (await SharedPreferences.getInstance()).setBool(
      'mobile.wifi_downloads',
      value,
    );
    notifyListeners();
  }

  Future<void> setVisualMotion(bool value) async {
    visualMotion = value;
    await (await SharedPreferences.getInstance()).setBool(
      'mobile.visual_motion',
      value,
    );
    notifyListeners();
  }

  Future<void> setAnalytics(bool value) async {
    analyticsConsent = value;
    await (await SharedPreferences.getInstance()).setBool(
      'mobile.analytics_consent',
      value,
    );
    if (value) {
      await _startAnalytics();
    } else if (_analyticsReady) {
      await Posthog().optOut();
    }
    notifyListeners();
  }

  Future<void> _startAnalytics() async {
    if (posthogKey.isEmpty || !httpsHost(posthogHost) || !analyticsConsent)
      return;
    try {
      if (!_analyticsReady) {
        final PostHogConfig config = PostHogConfig(posthogKey)
          ..host = posthogHost
          ..captureApplicationLifecycleEvents = false
          ..sessionReplay = false;
        await Posthog().setup(config);
        _analyticsReady = true;
      }
      if (analyticsConsent)
        await Posthog().optIn();
      else
        await Posthog().optOut();
    } catch (_) {
      /* Aucun événement si le service n'est pas disponible. */
    }
  }

  Future<void> used(String feature) async {
    if (!_analyticsReady ||
        !analyticsConsent ||
        !<String>[
          'download_started',
          'studio_opened',
          'guide_background_enabled',
        ].contains(feature))
      return;
    try {
      await Posthog().capture(
        event: 'mobile_feature_used',
        properties: <String, Object>{'feature': feature},
      );
    } catch (_) {}
  }
}
