"""Run the exact model (current z29b vs Z30) on a synthetic scene; one update per frame (frame 0 = lock / template)."""
import sys, numpy as np
sys.path.insert(0, '.')
from scene import make
from model import Tracker

def run(frames, gt, z30):
    t = Tracker(z30, 640, 360); out = []
    for i, f in enumerate(frames):
        r = t.update(f); out.append((r['cx'], r['cy'], r['lock'], r.get('res'), r.get('ares'), r['note']))
    return out

if __name__ == '__main__':
    kw = dict(n=int(sys.argv[1]) if len(sys.argv) > 1 else 80, noise=float(sys.argv[2]) if len(sys.argv) > 2 else 7.0,
              speed=float(sys.argv[3]) if len(sys.argv) > 3 else 4.0,
              fade=int(sys.argv[4]) if len(sys.argv) > 4 else None)
    frames, gt = make(**kw)
    a = run(frames, gt, False); b = run(frames, gt, True)
    ea = [abs(x[0] - g[0]) + abs(x[1] - g[1]) for x, g in zip(a, gt)]
    eb = [abs(x[0] - g[0]) + abs(x[1] - g[1]) for x, g in zip(b, gt)]
    for i in range(len(frames)):
        if i % 5 == 0 or i == len(frames) - 1:
            print(f'{i:3d} gt {gt[i][0]:4d},{gt[i][1]:4d} | cur {a[i][0]:4d},{a[i][1]:4d} L{a[i][2]} res {a[i][3]} {a[i][5]:7s} err {ea[i]:3d} | z30 {b[i][0]:4d},{b[i][1]:4d} L{b[i][2]} res {b[i][3]} a {b[i][4]} {b[i][5]:7s} err {eb[i]:3d}')
    print('mean err cur %.1f max %d refresh %d lost %d | z30 mean %.1f max %d refresh %d lost/flat %d' % (
        np.mean(ea), max(ea), sum(x[5] == 'REFRESH' for x in a), sum(x[2] == 2 for x in a),
        np.mean(eb), max(eb), sum(x[5] == 'REFRESH' for x in b), sum(x[2] == 2 for x in b)))
