#!/usr/bin/env bash
# Banc NovaTube : VPN par application pour un seul émulateur jetable sur un runner Linux/KVM.
# start SERIAL PACKAGE OUT ; verify SERIAL PACKAGE OUT [PORT=18999] ; down|up|stop SERIAL PACKAGE OUT.
set -euo pipefail
action="${1:?action absente}"
serial="${2:?serial absent}"
pkg="${3:?paquet absent}"
out="$(mkdir -p "${4:?répertoire absent}" && realpath "$4")"
port="${5:-18999}"
[[ "$serial" =~ ^emulator-[0-9]+$ && "$pkg" =~ ^com\.sevenmotion\.novatube\.tv\.lab\.[a-z0-9.]+$ && "$port" =~ ^[0-9]+$ ]]
dir="$(cd "$(dirname "$0")" && pwd)"
adbdev=(adb -s "$serial")
state="${RUNNER_TEMP:-$(dirname "$out")}/ntqa-vpn-$serial"
mkdir -p -m 700 "$state"

install_helper() {
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:?SDK Android absent}}" bt jar
  bt="$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
  jar="$(find "$sdk/platforms" -maxdepth 2 -name android.jar | sort -V | tail -1)"
  test -f "$jar"
  mkdir -p "$state/java" "$state/dex"
  javac --release 8 -cp "$jar" -d "$state/java" "$dir/StartTunnel.java" "$dir/TestVpn.java"
  "$bt/d8" --lib "$jar" --min-api 26 --output "$state/dex" "$state"/java/test/novatube/vpn/*.class
  "$bt/aapt2" link -I "$jar" --manifest "$dir/AndroidManifest.xml" -o "$state/base.apk"
  (cd "$state/dex" && zip -q -j "$state/base.apk" classes.dex)
  "$bt/zipalign" -f 4 "$state/base.apk" "$state/align.apk"
  if [[ ! -f "$state/test.p12" ]]; then
    keytool -genkeypair -keystore "$state/test.p12" -storetype PKCS12 -storepass android \
      -keypass android -alias fixture -keyalg RSA -keysize 2048 -validity 7 -dname 'CN=Disposable VPN test'
  fi
  "$bt/apksigner" sign --ks "$state/test.p12" --ks-pass pass:android \
    --out "$state/helper.apk" "$state/align.apk"
  "${adbdev[@]}" install -r "$state/helper.apk"
  "${adbdev[@]}" shell appops set test.novatube.vpn ACTIVATE_VPN allow
}

up() {
  local dns lan="${NOVATUBE_VPN_LAN:-allow}"
  [[ "$lan" == allow || "$lan" == deny ]]
  # Utilise le résolveur IPv4 du runner quand son adresse est routable depuis le tunnel.
  dns="$(awk '$1=="nameserver" && $2 ~ /^[0-9]+\./ && $2 !~ /^127\./ {print $2; exit}' \
    /run/systemd/resolve/resolv.conf /etc/resolv.conf 2>/dev/null || true)"
  dns="${dns:-1.1.1.1}"
  "${adbdev[@]}" shell am start -W -n test.novatube.vpn/.StartTunnel \
    --es app "$pkg" --es key "$(cat "$state/key")" --es dns "$dns" --es lan "$lan" > /dev/null
  for _ in $(seq 1 40); do
    if "${adbdev[@]}" shell ip -4 addr show | tr -d '\r' | grep -q '192\.0\.2\.2/30' \
      && jq -e '.connected' "$out/tunnel.json" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  "${adbdev[@]}" logcat -d -s NovaVpnQA:E | tail -22
  return 1
}

case "$action" in
  start)
    "${adbdev[@]}" shell pm path "$pkg" | grep -q '^package:'
    install_helper
    openssl rand -hex 16 > "$state/key"
    chmod 600 "$state/key"
    echo "$(sysctl -n net.ipv4.ip_forward)" > "$state/original-ip-forward"
    sudo sysctl -qw net.ipv4.ip_forward=1
    sudo ip tuntap add dev ntqa0 mode tun user "$(id -un)"
    sudo ip address add 192.0.2.1/30 dev ntqa0
    sudo ip link set ntqa0 mtu 1280 up
    sudo iptables -w -t nat -I POSTROUTING -s 192.0.2.2/32 ! -o ntqa0 -j MASQUERADE
    sudo iptables -w -I FORWARD -i ntqa0 -s 192.0.2.2/32 -j ACCEPT
    sudo iptables -w -I FORWARD -o ntqa0 -d 192.0.2.2/32 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    # Un accès à la source de test par l'interface physique du runner ne peut servir la mire.
    sudo iptables -w -I INPUT ! -i ntqa0 -d 192.0.2.1/32 -p tcp -j REJECT
    sudo iptables -w -I INPUT -i ntqa0 -s 192.0.2.2/32 -d 192.0.2.1/32 -j ACCEPT
    nohup python3 "$dir/gateway.py" "$out/tunnel.json" "$state/key" \
      > "$out/gateway.log" 2>&1 < /dev/null &
    echo "$!" > "$state/gateway.pid"
    for _ in $(seq 1 15); do [[ -f "$out/tunnel.json" ]] && break; sleep 1; done
    test -f "$out/tunnel.json"
    up
    "${adbdev[@]}" shell dumpsys connectivity | tr -d '\r' | grep -i 'TRANSPORT_VPN\|Transports:.*VPN\|NovaTube VPN QA' > "$out/android-vpn.txt"
    ;;
  up) up ;;
  down) "${adbdev[@]}" shell am force-stop test.novatube.vpn ;;
  verify)
    "${adbdev[@]}" shell ip -4 addr show | tr -d '\r' | grep '192\.0\.2\.2/30' > "$out/android-tunnel-address.txt"
    jq -e --arg port "$port" '.connected and .tunnel_packets_from_android > 0 and .tunnel_packets_to_android > 0
      and .fixture_tcp[$port].media_get_packets > 0 and .fixture_tcp[$port].response_bytes > 131072' "$out/tunnel.json" > /dev/null
    jq --arg port "$port" '{source_ip,android_ip,fixture:.fixture_tcp[$port],tunnel_packets_from_android,tunnel_packets_to_android}' "$out/tunnel.json"
    ;;
  stop)
    "${adbdev[@]}" shell am force-stop test.novatube.vpn || true
    if [[ -f "$state/gateway.pid" ]]; then kill "$(cat "$state/gateway.pid")" 2>/dev/null || true; fi
    sudo iptables -w -D INPUT -i ntqa0 -s 192.0.2.2/32 -d 192.0.2.1/32 -j ACCEPT || true
    sudo iptables -w -D INPUT ! -i ntqa0 -d 192.0.2.1/32 -p tcp -j REJECT || true
    sudo iptables -w -D FORWARD -o ntqa0 -d 192.0.2.2/32 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT || true
    sudo iptables -w -D FORWARD -i ntqa0 -s 192.0.2.2/32 -j ACCEPT || true
    sudo iptables -w -t nat -D POSTROUTING -s 192.0.2.2/32 ! -o ntqa0 -j MASQUERADE || true
    sudo ip link del ntqa0 || true
    if [[ -f "$state/original-ip-forward" ]]; then sudo sysctl -qw "net.ipv4.ip_forward=$(cat "$state/original-ip-forward")"; fi
    ;;
  *) exit 2 ;;
esac
