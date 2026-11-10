#!/bin/bash
cd "$(dirname "$0")"
T=$1; shift
verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-lint -O1 --top-module tbd -Mdir objd28b_$T "$@" tbd28b.sv wm28b/mono_display6.sv wm28b/mono_window2.sv wm28b/mono_algorithms4.sv eram_model.v > bd28b_$T.log 2>&1 || { tail -30 bd_$T.log; exit 1; }
./objd28b_$T/Vtbd > /dev/null && mv panel.hex panel28b_$T.hex && wc -l panel28b_$T.hex
