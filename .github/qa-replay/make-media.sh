#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$1"
for mode in live replay; do
  color=blue; frequency=440
  if [[ $mode == replay ]]; then color=red; frequency=880; fi
  ffmpeg -hide_banner -loglevel error -y -f lavfi -i "color=c=$color:s=640x360:r=25" -f lavfi -i 'testsrc2=s=144x100:r=25' -f lavfi -i "sine=frequency=$frequency:sample_rate=48000" -filter_complex '[0:v][1:v]overlay=248:130[v]' -map '[v]' -map 2:a -t 100 -c:v libx264 -preset ultrafast -threads 2 -pix_fmt yuv420p -g 25 -c:a aac -ac 2 -b:a 96k -mpegts_flags +resend_headers -f mpegts "$1/$mode.ts"
done
