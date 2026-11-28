# Appelé dans le shell du banc. Un seul socket et un seul sink virtuel, sans carte matérielle.
pa_dir="$RUNNER_TEMP/pulse-zuno"
mkdir -p "$pa_dir" "$pa_dir/runtime" "$pa_dir/state"
chmod 700 "$pa_dir" "$pa_dir/runtime" "$pa_dir/state"
export PULSE_RUNTIME_PATH="$pa_dir/runtime" PULSE_STATE_PATH="$pa_dir/state"
export PULSE_SERVER="unix:$pa_dir/native" PULSE_SINK=zuno PULSE_SOURCE=zuno.monitor
pulseaudio -n --daemonize=yes --exit-idle-time=-1 \
  --load="module-native-protocol-unix socket=$pa_dir/native auth-anonymous=1" \
  --load="module-null-sink sink_name=zuno rate=48000 channels=2" \
  --log-target="file:$pa_dir/daemon.log"
pactl list short sinks | awk '$2=="zuno" {found=1} END {exit !found}'
pactl list short sources | awk '$2=="zuno.monitor" {found=1} END {exit !found}'
