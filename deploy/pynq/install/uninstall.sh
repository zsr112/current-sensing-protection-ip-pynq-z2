#!/bin/sh
set -eu
[ "${1:-}" = "--confirm" ] || { echo "usage: sudo ./uninstall.sh --confirm" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "root required" >&2; exit 1; }
SERVICE=current-sensing-protection-ip-load.service
if systemctl is-active --quiet "$SERVICE"; then
    echo "service is active; stop and review manually before uninstall" >&2
    exit 1
fi
RID=S1E-ENGINEERING-ARTIFACTS-20260725T070234792Z
VERIFY=/usr/local/libexec/current-sensing-protection-ip/verify_installed_release.py
[ -x "$VERIFY" ] || { echo "installed verifier missing; stop for review" >&2; exit 1; }
"$VERIFY" --release-path "/opt/current-sensing-protection-ip/releases/$RID" --releases-root /opt/current-sensing-protection-ip/releases
systemctl disable "$SERVICE"
rm -f /etc/systemd/system/current-sensing-protection-ip-load.service
rm -f /usr/local/libexec/current-sensing-protection-ip/load_current_release.py
rm -f /usr/local/libexec/current-sensing-protection-ip/load_current_release_once.sh
rm -f /usr/local/libexec/current-sensing-protection-ip/verify_installed_release.py
if [ -L /opt/current-sensing-protection-ip/current ]; then rm -f /opt/current-sensing-protection-ip/current; fi
rm -rf "/opt/current-sensing-protection-ip/releases/$RID"
systemctl daemon-reload
echo "release runtime removed; logs and state were preserved for review"
