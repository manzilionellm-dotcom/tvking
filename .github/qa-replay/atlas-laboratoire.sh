# Inclus par le banc de test sur un émulateur Android 11 vierge et temporaire.
# Le Worker et son certificat sont exclusivement locaux à cet espace réseau sans route externe.
lab="$RUNNER_TEMP/atlas-local-replay"
mkdir -p "$lab"; chmod 700 "$lab"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -keyout "$lab/ca.key" -out "$lab/ca.pem" -subj '/CN=NovaTube isolated Android QA root' -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign' 2>/dev/null
openssl req -new -newkey rsa:2048 -nodes -keyout "$lab/server.key" -out "$lab/server.csr" -subj '/CN=api.zuno8k.com' 2>/dev/null
printf '%s\n' 'subjectAltName=DNS:api.zuno8k.com' 'basicConstraints=CA:FALSE' 'extendedKeyUsage=serverAuth' > "$lab/extensions"
openssl x509 -req -days 1 -in "$lab/server.csr" -CA "$lab/ca.pem" -CAkey "$lab/ca.key" -CAcreateserial -extfile "$lab/extensions" -out "$lab/server.pem" 2>/dev/null
isolated env ATLAS_PORT=8788 "$(command -v node)" android-app/ci/novatube_tv/atlas_local_server.mjs atlas/android-app/cloudflare "$lab/worker.json" > "$lab/worker.log" 2>&1 &
for k in {1..60};do [[ -s "$lab/worker.json" ]] && break; sleep 1; done
if [[ ! -s "$lab/worker.json" ]]; then tail -18 "$lab/worker.log";exit 1;fi
isolated /usr/bin/python3 .github/qa-replay/tls-atlas.py "$lab" "$out/atlas-local.jsonl" > "$lab/tls.log" 2>&1 &
serial_adb root;serial_adb wait-for-device
test "$(serial_adb shell id -u | tr -d '\r')" = 0
hash=$(openssl x509 -noout -subject_hash_old -in "$lab/ca.pem")
# Les points de montage sont propres à cet émulateur éphémère. Aucune requête ne sort du réseau de laboratoire.
serial_adb shell 'mkdir -p /data/local/tmp/nova-ca && cp -a /system/etc/security/cacerts/. /data/local/tmp/nova-ca/'
serial_adb push "$lab/ca.pem" "/data/local/tmp/nova-ca/$hash.0" >/dev/null
serial_adb exec-out cat /system/etc/hosts > "$lab/hosts";printf '\n127.0.0.1 api.zuno8k.com\n' >> "$lab/hosts";serial_adb push "$lab/hosts" /data/local/tmp/nova-hosts >/dev/null
serial_adb shell 'chmod 755 /data/local/tmp/nova-ca; chmod 644 /data/local/tmp/nova-ca/* /data/local/tmp/nova-hosts; chcon -R u:object_r:system_file:s0 /data/local/tmp/nova-ca; chcon u:object_r:system_file:s0 /data/local/tmp/nova-hosts'
cat > "$lab/mount-qa.sh" <<'GUEST'
#!/system/bin/sh
set -eu
namespaces=' '
for p in 1 $(pidof zygote64 || true) $(pidof zygote || true); do
  m=$(readlink /proc/$p/ns/mnt)
  case "$namespaces" in *" $m "*) continue;; esac
  namespaces="$namespaces$m "
  nsenter -t "$p" -m -- mount -o bind /data/local/tmp/nova-ca /system/etc/security/cacerts
  nsenter -t "$p" -m -- mount -o bind /data/local/tmp/nova-hosts /system/etc/hosts
done
GUEST
serial_adb push "$lab/mount-qa.sh" /data/local/tmp/nova-mount.sh >/dev/null
serial_adb shell sh /data/local/tmp/nova-mount.sh
serial_adb shell ls "/system/etc/security/cacerts/$hash.0"
serial_adb shell ping -c 1 -W 1 api.zuno8k.com | head -4
serial_adb reverse tcp:443 tcp:8743
isolated curl --silent --show-error --cacert "$lab/ca.pem" --resolve api.zuno8k.com:8743:127.0.0.1 https://api.zuno8k.com:8743/ -o /dev/null
