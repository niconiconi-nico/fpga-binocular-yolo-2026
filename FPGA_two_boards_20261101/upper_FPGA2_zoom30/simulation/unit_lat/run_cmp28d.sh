#!/bin/bash
cd "$(dirname "$0")"
for s in z25 z28d; do ./run_tbr.sh $s 0 65536; ./run_tbr.sh $s 1 32768; done
for c in 0_65536 1_32768; do cmp r_z25/out_$c.txt r_z28d/out_$c.txt && echo SAME_$c; wc -l < r_z28d/out_$c.txt; done
