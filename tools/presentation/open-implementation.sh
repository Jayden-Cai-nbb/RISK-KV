#!/usr/bin/env bash
# Offline inspection only. Never connects to hardware or writes a checkpoint/bitstream.
set -euo pipefail
rkv_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
rkv_mode=gui
if [[ ${1:-} == --batch-check ]]; then
    rkv_mode=batch
elif [[ $# != 0 ]]; then
    printf '%s\n' 'Usage: bash tools/presentation/open-implementation.sh [--batch-check]' >&2
    exit 2
fi
if [[ $rkv_mode == gui && -z ${DISPLAY:-} ]]; then
    printf '%s\n' '请在服务器图形桌面的新终端运行此命令；当前 SSH 没有图形显示。' >&2
    exit 2
fi
python3 "$rkv_root/tools/presentation/recording_view.py" implementation
mkdir -p "$rkv_root/build/reproduction/recording-20261108"
rkv_out="$(mktemp -d "$rkv_root/build/reproduction/recording-20261108/offline-${rkv_mode}-XXXXXX")"
printf 'Offline inspection reports: %s\n' "$rkv_out"
cd -- "$rkv_out"
exec "${VIVADO_BIN:-vivado}" -mode "$rkv_mode" \
    -source "$rkv_root/tools/presentation/inspect-implementation.tcl" -tclargs "$rkv_mode"
