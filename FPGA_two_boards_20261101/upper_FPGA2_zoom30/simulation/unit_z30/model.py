"""CLAUDE Z30: exact integer model of range_meter TEMPLATE 48 tracking (track_only, !rwin), current (z29b) and Z30.
Window of an update armed at (bx, by): rows y = by - 48 + r (r 0..95), columns x = bx - 48 - ox + c (c 0..103),
ox = bx mod 4. Block (r0, c0) = 32 x 32 at window (r0, c0); its centre = (bx - 48 - ox + c0 + 16, by - 48 + r0 + 16).
All sums, means (>> 10), rank / tie rules, clamps and decisions follow the RTL (see range_meter.sv S_TMEAN .. S_COPY)."""
import numpy as np

MAXRES, REFRES, TEXMIN = 28, 16, 24

class Tracker:
    def __init__(self, z30, cx, cy):
        self.z30 = z30; self.cx, self.cy = cx, cy
        self.T = None; self.A = None; self.lock = 1; self.tinit = True

    def win(self, img, bx, by):
        ox = bx & 3
        x0 = bx - 48 - ox; y0 = by - 48
        return img[y0:y0 + 96, x0:x0 + 104].astype(np.int64), ox

    def update(self, img):
        bx, by = self.cx, self.cy
        W, ox = self.win(img, bx, by)
        blk = lambda r0, c0: W[r0:r0 + 32, c0:c0 + 32]
        if self.tinit:                                   # S_WAITL tinit -> S_COPY (template and anchor)
            self.tinit = False
            self.T = blk(32, ox + 32).copy(); self.A = self.T.copy()
            return dict(cx=self.cx, cy=self.cy, lock=self.lock, res=None, note='init')
        T = self.T
        tmean = int(T.sum()) >> 10
        # coarse: candidates (cu, cv) 0..32, block (2cv, ox + 2cu), samples (2a, 2b)
        best = None
        for cv in range(33):
            for cu in range(33):
                s = int(np.abs(T[0:32:2, 0:32:2] - W[2 * cv:2 * cv + 32:2, ox + 2 * cu:ox + 2 * cu + 32:2]).sum())
                d = abs(cu - 16) + abs(cv - 16)
                r = s + d * 128
                if best is None or r < best[0] or (r == best[0] and d < best[1]): best = (r, d, cu, cv)
        _, _, cub, cvb = best
        def fine(tpl, cand):
            tm = int(tpl.sum()) >> 10
            fb = None
            for fk in range(9):
                fr0, fc0 = cand(fk)
                b = blk(fr0, fc0)
                wm = int(b.sum()) >> 10
                s = int(np.abs(tpl - b - tm + wm).sum())
                d = abs(fr0 - 32) + abs(fc0 - 32 - ox)
                r = s + d * 256
                if fb is None or r < fb[0] or (r == fb[0] and d < fb[1]): fb = (r, d, s, fr0, fc0)
            return fb[2] >> 10, fb[3], fb[4]
        def cur_cand(fk):
            fv7 = 2 * cvb + fk // 3; fu7 = 2 * cub + fk % 3
            fr0 = 0 if fv7 == 0 else (64 if fv7 - 1 > 64 else fv7 - 1)
            fc0 = ox if fu7 == 0 else (ox + 64 if fu7 - 1 > 64 else ox + fu7 - 1)
            return fr0, fc0
        res, frb, fcb = fine(T, cur_cand)
        info = dict(res=res)
        def centre(fr, fc):
            ncx = bx + fc - ox - 32; ncy = by + fr - 32
            ncx = min(max(ncx, 64), 1212); ncy = min(max(ncy, 64), 652)
            return ncx, ncy
        if res >= MAXRES:
            self.lock = 2; info.update(cx=self.cx, cy=self.cy, lock=2, note='LOST'); return info
        cres = res; anc_ok = True
        if self.z30:
            crb, ccb = frb, fcb
            def anc_cand(fk):
                ar7 = crb + fk // 3; ac7 = ccb + fk % 3
                fr0 = 0 if ar7 == 0 else (64 if ar7 - 1 > 64 else ar7 - 1)
                fc0 = ox if ac7 <= ox else (ox + 64 if ac7 - 1 > ox + 64 else ac7 - 1)
                return fr0, fc0
            ares, arb, acb = fine(self.A, anc_cand)
            info['ares'] = ares
            anc_ok = ares < MAXRES
            if anc_ok: frb, fcb = arb, acb
            b = blk(frb, fcb)
            if int(b.max()) - int(b.min()) < TEXMIN:
                self.lock = 2; info.update(cx=self.cx, cy=self.cy, lock=2, note='FLAT'); return info
        ncx, ncy = centre(frb, fcb)
        still = abs(ncx - self.cx) <= 1 and abs(ncy - self.cy) <= 1
        self.lock = 1
        refresh = (not still) and cres >= REFRES and anc_ok
        if not still: self.cx, self.cy = ncx, ncy
        if refresh: self.T = blk(frb, fcb).copy()
        info.update(cx=self.cx, cy=self.cy, lock=1, note='REFRESH' if refresh else '')
        return info
