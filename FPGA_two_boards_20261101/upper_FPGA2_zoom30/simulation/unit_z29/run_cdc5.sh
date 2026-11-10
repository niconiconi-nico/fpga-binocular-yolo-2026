#!/bin/bash
cd "$(dirname "$0")"
c(){ T=$1; shift; ./run.sh $T input29b frame_publish_cdc5 -GPEND_LAST=1 "$@" | grep FINAL; }
c c5_a &
c c5_p1 -GPACED=1 -GDRAIN=1000.0 &
c c5_p2 -GPACED=1 -GDRAIN=2000.0 &
c c5_p3 -GPACED=1 -GDRAIN=3000.0 &
wait
c c5_p8 -GPACED=1 -GDRAIN=8000.0 &
c c5_b -GTSEND=52000.0 -GTDISP=52000.0 &
c c5_c -GTSEND=52000.0 -GTDISP=65000.0 &
c c5_d -GTSEND=100000.0 &
wait
