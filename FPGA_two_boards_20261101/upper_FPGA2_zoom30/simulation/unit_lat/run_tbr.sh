#!/bin/bash
# reader pixel test (unit_zoom/tbr.sv) with the stage_<S> reader: run_tbr.sh <S> <ZOOM_EN> <STEP>
cd "$(dirname "$0")"
S=$1; Z=$2; ST=$3; D=r_$S
mkdir -p $D
for f in stereo_raw_reader1 stereo_line_cache3 reset_domain_sync; do sed 's#G:/anlogic#/mnt/g/anlogic#g' ../stage_$S/rtl/$f.sv > $D/w_$f.sv; done
verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-lint -O2 --top-module tbr -Mdir $D/obj_${Z}_$ST -GZOOM_EN=$Z -GSTEP=$ST ../unit_zoom/tbr.sv $D/w_stereo_raw_reader1.sv $D/w_stereo_line_cache3.sv $D/w_reset_domain_sync.sv > $D/b_${Z}_$ST.log 2>&1 || { tail -20 $D/b_${Z}_$ST.log; exit 1; }
./$D/obj_${Z}_$ST/Vtbr > $D/out_${Z}_$ST.txt; tail -3 $D/out_${Z}_$ST.txt
