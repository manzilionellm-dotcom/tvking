#!/usr/bin/env bash
set -euo pipefail
out=${1:?dossier de mire vide}
seconds=${2:-6}
case "$seconds" in 6|600) ;; *) exit 2;; esac
mkdir -p "$out"
cd "$out"
if [[ -e media.m3u8 ]]; then exit 2; fi
ffmpeg -hide_banner -loglevel error -nostdin \
  -f lavfi -i "color=c=navy:s=1280x720:r=25,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='ZUNO LAB %{n}':fontcolor=white:fontsize=58:x=80:y=240" \
  -f lavfi -i sine=frequency=440:sample_rate=48000 -t "$seconds" \
  -c:v libx264 -preset ultrafast -threads 1 -g 50 -sc_threshold 0 \
  -pix_fmt yuv420p -c:a aac -b:a 64k -f hls -hls_time 2 -hls_list_size 0 \
  -hls_playlist_type vod -hls_segment_filename 'p%04d.ts' media.m3u8
