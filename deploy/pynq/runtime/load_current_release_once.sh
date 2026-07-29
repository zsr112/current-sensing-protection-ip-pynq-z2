#!/bin/sh
set -eu
export PYTHONDONTWRITEBYTECODE=1

s1g_wrapper_boundary=wrapper_entry
s1g_wrapper_audit() {
    printf 'S1G_WRAPPER_EVENT\tprotocol_version=1\tevent=%s\tstatus=%s\texit_code=%s\tboundary=%s\tshell_pid=%s\n' \
        "$1" "$2" "$3" "$4" "$$" >&2
}
s1g_wrapper_on_exit() {
    s1g_wrapper_status=$?
    if [ "$s1g_wrapper_status" -ne 0 ]; then
        s1g_wrapper_audit wrapper_fail FAIL "$s1g_wrapper_status" "$s1g_wrapper_boundary"
    fi
}
trap s1g_wrapper_on_exit EXIT
s1g_wrapper_audit wrapper_entry ENTER 0 "$s1g_wrapper_boundary"

if [ "$(id -u)" -ne 0 ]; then
    echo "current-sensing-protection-ip loader requires root" >&2
    exit 1
fi

if [ ! -r /etc/profile.d/xrt_setup.sh ]; then
    echo "missing /etc/profile.d/xrt_setup.sh" >&2
    exit 1
fi
s1g_wrapper_audit wrapper_entry EXIT 0 "$s1g_wrapper_boundary"

s1g_wrapper_boundary=xrt_setup
s1g_wrapper_audit xrt_setup_enter ENTER 0 "$s1g_wrapper_boundary"
. /etc/profile.d/xrt_setup.sh

if [ "${XILINX_XRT:-}" != "/usr" ]; then
    echo "XILINX_XRT must be exactly /usr" >&2
    exit 1
fi
s1g_wrapper_audit xrt_setup_exit EXIT 0 "$s1g_wrapper_boundary"

s1g_wrapper_boundary=python_exec
s1g_wrapper_audit python_exec ENTER 0 "$s1g_wrapper_boundary"
exec /usr/local/share/pynq-venv/bin/python3 -B \
    /usr/local/libexec/current-sensing-protection-ip/load_current_release.py \
    --supervise
