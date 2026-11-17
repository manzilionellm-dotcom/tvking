#!/usr/bin/env bash
# =========================================================
#  make_test_media.sh — Liste M3U de TEST 100 % autorisée (mires générées)
# =========================================================
#  Usage : bash ci/novatube_tv/make_test_media.sh <dossier>
#
#  Aucune chaîne réelle, aucun fournisseur, aucun identifiant : tout est
#  FABRIQUÉ ici par ffmpeg (mires de couleur + bip 440 Hz). Ces fichiers
#  servent uniquement au contrôle sur émulateur, servis en local
#  (http://127.0.0.1:8080) et jamais publiés dans le dépôt.
#
#  Contenu :
#    live/mire1/index.m3u8   HLS 1080p25 H.264 + AAC stéréo (« testsrc2 »)
#    live/mire2/index.m3u8   HLS 1080p25 H.264 + AAC (barres SMPTE HD)
#    logos/mire{1,2,3}.png   logos 256×256
#    novatube-test.m3u       3 chaînes, 1 film et 1 épisode générés, avec logos
# =========================================================
set -euo pipefail
dir="$(mkdir -p "$1" && readlink -f "$1")"
mkdir -p "$dir/live/mire1" "$dir/live/mire2" "$dir/logos" "$dir/movie" "$dir/series"

hls() { # $1 = source vidéo lavfi, $2 = dossier de sortie
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "$1" -f lavfi -i "sine=frequency=440:sample_rate=48000" \
    -t 180 -map 0:v -map 1:a \
    -c:v libx264 -preset veryfast -profile:v high -pix_fmt yuv420p -g 50 -keyint_min 50 \
    -c:a aac -b:a 128k -ac 2 \
    -f hls -hls_time 2 -hls_playlist_type vod \
    -hls_segment_filename "$2/seg%03d.ts" "$2/index.m3u8"
}
hls "testsrc2=size=1920x1080:rate=25" "$dir/live/mire1"
hls "smptehdbars=size=1920x1080:rate=25" "$dir/live/mire2"

ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc=size=256x256:rate=1" -frames:v 1 "$dir/logos/mire1.png"
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "smptebars=size=256x256:rate=1" -frames:v 1 "$dir/logos/mire2.png"
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "color=c=0x0B2A24:size=256x256:rate=1" -frames:v 1 "$dir/logos/mire3.png"

# Les deux titres de contrôle contiennent seulement la mire locale déjà créée.
ffmpeg -hide_banner -loglevel error -y -i "$dir/live/mire2/index.m3u8" \
  -c copy -movflags +faststart "$dir/movie/horizon.mp4"
ln -f "$dir/movie/horizon.mp4" "$dir/series/aurora.mp4"

base="http://127.0.0.1:8080"
cat > "$dir/novatube-test.m3u" <<EOF
#EXTM3U
#EXTINF:-1 tvg-id="test.mire1" tvg-logo="$base/logos/mire1.png" group-title="Test NovaTube",Mire de test 1080p
$base/live/mire1/index.m3u8
#EXTINF:-1 tvg-id="test.mire2" tvg-logo="$base/logos/mire2.png" group-title="Test NovaTube",Barres HD de test
$base/live/mire2/index.m3u8
#EXTINF:-1 tvg-id="test.mire3" tvg-logo="$base/logos/mire3.png" group-title="Démo",Mire de test (copie)
$base/live/mire1/index.m3u8
#EXTINF:-1 tvg-id="test.film" tvg-logo="$base/logos/mire2.png" group-title="Z Films",Horizon
$base/movie/horizon.mp4
#EXTINF:-1 tvg-id="test.episode" tvg-logo="$base/logos/mire3.png" group-title="Z Series",Aurora S01E01
$base/series/aurora.mp4
EOF
ls -R "$dir" | head -20
