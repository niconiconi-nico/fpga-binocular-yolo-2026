#!/bin/bash
# usage: run.sh <tag> [verilator -G overrides...]
cd "$(dirname "$0")"
T=$1; shift
S=../stage_z25/rtl
for f in stereo_raw_reader1 stereo_line_cache3 reset_domain_sync local_native_commit1 latency_meter1; do sed 's#G:/anlogic#/mnt/g/anlogic#g' $S/$f.sv > w_$f.sv; done
verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-lint -O2 --top-module tbl -Mdir obj_$T "$@" tbl.sv w_stereo_raw_reader1.sv w_stereo_line_cache3.sv w_reset_domain_sync.sv w_local_native_commit1.sv w_latency_meter1.sv > build_$T.log 2>&1 || { tail -30 build_$T.log; exit 1; }
./obj_$T/Vtbl | tail -12
