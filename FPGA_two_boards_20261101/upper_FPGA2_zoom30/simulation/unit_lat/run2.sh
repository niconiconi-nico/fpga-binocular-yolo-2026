#!/bin/bash
# usage: run2.sh <tag> [verilator -G overrides...]   (Z27 meter: stage_z27/rtl/latency_meter2.sv, rest from stage_z25)
cd "$(dirname "$0")"
T=$1; shift
S=../stage_z25/rtl
for f in stereo_raw_reader1 stereo_line_cache3 reset_domain_sync local_native_commit1; do sed 's#G:/anlogic#/mnt/g/anlogic#g' $S/$f.sv > w_$f.sv; done
cp ../stage_z27/rtl/latency_meter2.sv w_latency_meter2.sv
verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-lint -O2 --top-module tbl -Mdir obj2_$T "$@" tbl2.sv w_stereo_raw_reader1.sv w_stereo_line_cache3.sv w_reset_domain_sync.sv w_local_native_commit1.sv w_latency_meter2.sv > build2_$T.log 2>&1 || { tail -30 build2_$T.log; exit 1; }
./obj2_$T/Vtbl | tail -16
