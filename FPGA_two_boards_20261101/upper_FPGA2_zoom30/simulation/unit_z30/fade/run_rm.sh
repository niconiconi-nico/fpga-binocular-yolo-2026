#!/bin/bash
# run_rm.sh <tag> <range_meter.sv path> [NUPD]
cd "$(dirname "$0")"
T=$1; R=$2; N=${3:-40}
verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-lint -Wno-MULTIDRIVEN -O2 --top-module tb_rm -Mdir obj_$T -GNUPD=$N -GBLANK=${4:-300000} tb_rm.sv $R > build_$T.log 2>&1 || { tail -20 build_$T.log; exit 1; }
./obj_$T/Vtb_rm | tail -2
cp rtl_log.txt rtl_log_$T.txt
