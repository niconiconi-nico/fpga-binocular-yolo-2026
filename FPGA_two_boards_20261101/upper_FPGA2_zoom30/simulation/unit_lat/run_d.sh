#!/bin/bash
cd "$(dirname "$0")"
T=$1; shift
verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-lint -O1 --top-module tbd -Mdir objd_$T "$@" tbd.sv wm/mono_display6.sv wm/mono_window2.sv wm/mono_algorithms4.sv eram_model.v > bd_$T.log 2>&1 || { tail -30 bd_$T.log; exit 1; }
./objd_$T/Vtbd > /dev/null && mv panel.hex panel_$T.hex && wc -l panel_$T.hex
