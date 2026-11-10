#!/bin/bash
# run.sh <tag> <input dir> <cdc file> [extra verilator args]
cd "$(dirname "$0")"
T=$1; I=../$2; C=$3; shift 3
mkdir -p w_$T
rm -f w_$T/*.sv; for f in remote_media_ingress5 checked_media_ethernet_rx3 video_udp_receiver $C reset_domain_sync; do sed 's#G:/anlogic#/mnt/g/anlogic#g' $I/rtl/$f.sv > w_$T/$f.sv; done
verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-lint -O2 --top-module tbo -Mdir obj_$T +define+CDCNAME=\"$T\" "$@" tbo.sv w_$T/*.sv > build_$T.log 2>&1 || { tail -20 build_$T.log; exit 1; }
./obj_$T/Vtbo | tail -12
