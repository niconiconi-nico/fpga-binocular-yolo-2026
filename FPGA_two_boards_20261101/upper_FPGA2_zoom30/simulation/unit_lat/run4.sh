#!/bin/bash
# usage: run2.sh <tag> [verilator -G overrides...]   (Z28B meter: stage_z28b/rtl/latency_meter4.sv, rest from stage_z25)
cd "$(dirname "$0")"
T=$1; shift
S=../stage_z25/rtl
for f in stereo_raw_reader1 stereo_line_cache3 reset_domain_sync local_native_commit1; do sed 's#G:/anlogic#/mnt/g/anlogic#g' $S/$f.sv > w_$f.sv; done
cp ../stage_z28b/rtl/latency_meter4.sv w_latency_meter4.sv
verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-lint -O2 --top-module tbl -Mdir obj4_$T "$@" tbl4.sv w_stereo_raw_reader1.sv w_stereo_line_cache3.sv w_reset_domain_sync.sv w_local_native_commit1.sv w_latency_meter4.sv > build4_$T.log 2>&1 || { tail -30 build4_$T.log; exit 1; }
./obj4_$T/Vtbl | tail -40
