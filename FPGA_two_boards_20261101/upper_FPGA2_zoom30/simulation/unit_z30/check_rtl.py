"""Replay the RTL log (capture frame index per tracking result) through the exact model and compare cx, cy, lock."""
import sys, numpy as np
sys.path.insert(0, '.')
from model import Tracker
z30 = sys.argv[1] == 'z30'; log = sys.argv[2]; n = int(sys.argv[3])
frames = np.fromfile('frames.bin', np.uint8).reshape(-1, 720, 1280)
gt = np.load('gt.npy')
rows = [list(map(int, l.split())) for l in open(log) if l.strip()]
rows = [r for r in rows if r[3] != 0]
t = Tracker(z30, 640, 360); bad = 0; errs = []
for i, (fi, cx, cy, lk, tg) in enumerate(rows):
    m = t.update(frames[fi].astype(np.int64))
    ok = (m['cx'], m['cy'], m['lock']) == (cx, cy, lk)
    bad += not ok
    e = abs(cx - gt[fi][0]) + abs(cy - gt[fi][1]); errs.append(e)
    if not ok or i % 5 == 0:
        print(f'{i:3d} frame {fi:3d} rtl {cx:4d},{cy:4d} L{lk} tg{tg} | model {m["cx"]:4d},{m["cy"]:4d} L{m["lock"]} {m.get("note","")} res {m.get("res")} a {m.get("ares")} | gt {gt[fi][0]},{gt[fi][1]} err {e} {"" if ok else "MISMATCH"}')
print(f'{"Z30" if z30 else "Z29B"} updates={len(rows)} mismatches={bad} mean_err={np.mean(errs[1:]):.1f} max_err={max(errs[1:])} {"PASS" if bad == 0 and len(rows) >= n else "FAIL"}')
