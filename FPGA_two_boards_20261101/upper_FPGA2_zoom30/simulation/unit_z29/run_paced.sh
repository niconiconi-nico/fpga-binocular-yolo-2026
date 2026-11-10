#!/bin/bash
cd "$(dirname "$0")"
c(){ T=$1; I=$2; C=$3; shift 3; ./run.sh $T $I $C "$@" | grep FINAL; }
c p4_1 input29 frame_publish_cdc4 -GPACED=1 -GDRAIN=1000.0 &
c p4_2 input29 frame_publish_cdc4 -GPACED=1 -GDRAIN=2000.0 &
c p4_3 input29 frame_publish_cdc4 -GPACED=1 -GDRAIN=3000.0 &
c p3_1 input28d frame_publish_cdc3 -GPACED=1 -GDRAIN=1000.0 &
wait
