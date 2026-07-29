#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo "root required" >&2; exit 1; }
HERE=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -P "$HERE/../.." && pwd)
PYTHON=/usr/local/share/pynq-venv/bin/python3
[ -x "$PYTHON" ] || { echo "PYNQ Python 3.10.4 is required" >&2; exit 1; }
"$PYTHON" "$ROOT/tools/verify_release.py" "$ROOT"
RID=S1E-ENGINEERING-ARTIFACTS-20260725T070234792Z
DEPLOY=/opt/current-sensing-protection-ip
FINAL="$DEPLOY/releases/$RID"
[ ! -e "$FINAL" ] || { echo "installed release already exists; stop for review" >&2; exit 1; }
install -d -m 0755 "$DEPLOY/releases" /usr/local/libexec/current-sensing-protection-ip /etc/systemd/system
TEMP="$DEPLOY/releases/.$RID.$$"
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM
install -d -m 0555 "$TEMP"
for name in protection_system.bit protection_system.hwh release_manifest.json release_manifest.sha256; do
    install -m 0444 "$ROOT/pynq/artifacts/$name" "$TEMP/$name"
done
mv "$TEMP" "$FINAL"
trap - EXIT HUP INT TERM
for name in load_current_release.py load_current_release_once.sh verify_installed_release.py; do
    install -m 0755 "$ROOT/pynq/runtime/$name" "/usr/local/libexec/current-sensing-protection-ip/$name"
done
install -m 0644 "$ROOT/pynq/systemd/current-sensing-protection-ip-load.service" /etc/systemd/system/current-sensing-protection-ip-load.service
ln -s "releases/$RID" "$DEPLOY/.current.$$"
mv -Tf "$DEPLOY/.current.$$" "$DEPLOY/current"
systemctl daemon-reload
systemctl enable current-sensing-protection-ip-load.service
echo "installed and enabled; service was not started and no reboot was issued"
