#!/bin/sh
set -eu
HERE=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -P "$HERE/../.." && pwd)
python3 "$ROOT/tools/verify_release.py" "$ROOT"
RID=S1E-ENGINEERING-ARTIFACTS-20260725T070234792Z
VERIFY=/usr/local/libexec/current-sensing-protection-ip/verify_installed_release.py
if [ -x "$VERIFY" ]; then
    "$VERIFY" --release-path "/opt/current-sensing-protection-ip/releases/$RID" --releases-root /opt/current-sensing-protection-ip/releases
else
    echo "installed runtime verifier is absent"
fi
systemctl is-enabled current-sensing-protection-ip-load.service || true
systemctl is-active current-sensing-protection-ip-load.service || true
