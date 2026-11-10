#!/bin/bash
# extra timing cases for the three-bank (cdc4) receive path, plus cdc3 at equal rates for reference
cd "$(dirname "$0")"
c(){ T=$1; I=$2; C=$3; shift 3; ./run.sh $T $I $C "$@" | grep FINAL; }
c cdc4_b input29 frame_publish_cdc4 -GTSEND=52000.0 -GTDISP=52000.0 &
c cdc4_c input29 frame_publish_cdc4 -GTSEND=52000.0 -GTDISP=65000.0 &
c cdc4_d input29 frame_publish_cdc4 -GTSEND=100000.0 -GTDISP=49977.0 &
c cdc4_e input29 frame_publish_cdc4 -GDRAIN=8000.0 &
c cdc3_b input28d frame_publish_cdc3 -GTSEND=52000.0 -GTDISP=52000.0 &
wait
