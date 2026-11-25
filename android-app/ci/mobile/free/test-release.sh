#!/usr/bin/env bash
# La recette Play et les APK de test exécutent les mêmes régressions sur le correctif assemblé.
set -euo pipefail
flutter test --no-pub --reporter expanded --dart-define=PLAY_BUILD=true \
  test/free_play \
  test/core/app/boot_without_optional_plugins_test.dart \
  test/core/observability/early_diagnostics_test.dart \
  test/core/playback/stream_slot_test.dart \
  test/features/channels/channel_metadata_isolate_test.dart \
  test/features/device/device_identity_adopt_test.dart \
  test/features/playlists/panel_getphp_reconcile_test.dart \
  test/features/playlists/panel_source_decision_test.dart \
  test/features/playlists/m3u_catalogue_refresh_test.dart \
  test/features/playlists/m3u_fetcher_failure_test.dart \
  test/features/playlists/m3u_parser_test.dart \
  test/features/playlists/m3u_stream_parity_test.dart \
  test/features/playlists/multiple_active_sources_test.dart \
  test/features/playlists/playlist_database_migration_test.dart \
  test/features/playlists/source_calibrator_test.dart \
  test/features/playlists/xtream_account_info_test.dart \
  test/features/playlists/xtream_client_test.dart \
  test/features/playlists/xtream_url_format_store_test.dart \
  test/features/player/hls_playback_test.dart \
  test/features/player/local_stream_relay_wave2_test.dart \
  test/features/player/one_connection_zapping_test.dart \
  test/features/player/phone_video_test.dart \
  test/features/player/playback_transition_integration_test.dart \
  test/features/player/playback_transition_test.dart \
  test/features/player/upstream_placeholder_test.dart
