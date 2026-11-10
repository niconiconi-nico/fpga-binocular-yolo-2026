"""CLAUDE Z30 synthetic TEMPLATE scenes (grey 1280x720 uint8). A light, weakly textured 'cup' (90 x 140) carrying a dark
'logo' (two rows of letter-like strokes, ~60 x 26) moves over a checker / dot background; per frame: sensor noise,
global brightness wobble, horizontal motion blur proportional to the speed. The logo centre starts at (640, 360) (the
reset lock point pos 4). Ground truth = logo centre per frame."""
import numpy as np

def make(n=80, seed=1, noise=7.0, wobble=10.0, speed=4.0, blur=True, fade=None):   # fade: logo fades out from this frame (cup turns)
    rng = np.random.default_rng(seed)
    H, W = 720, 1280
    yy, xx = np.mgrid[0:H, 0:W]
    bg = 150 + 40 * (((xx // 40) + (yy // 40)) % 2) - 20               # checkerboard 40 px
    dots = ((xx % 24 - 12) ** 2 + (yy % 24 - 12) ** 2) < 16
    bg = np.where((xx > 700) & (yy > 380) & dots, 60, bg).astype(np.float64)
    cup = 205 + 6 * np.sin(np.mgrid[0:140, 0:90][0] / 9.0)            # weak vertical shading only
    logo = np.zeros((26, 60))
    rs = np.random.default_rng(7)
    for k in range(9):                                                 # letter-like strokes
        x0 = 2 + k * 6 + rs.integers(0, 2); h = rs.integers(8, 12)
        logo[1:1 + h, x0:x0 + 3] = 1; logo[14:14 + rs.integers(8, 11), x0 + 1:x0 + 4] = 1
        if k % 2: logo[1:4, x0:x0 + 6] = 1
    plain = cup.copy()
    cup[50:76, 15:75] = np.where(logo > 0, 95, cup[50:76, 15:75])     # logo dark (red on white -> luma ~95)
    # path: logo centre (cx, cy); the cup is placed so the logo centre is at cup (63, 45)
    t = np.arange(n)
    cx = 640 + 120 * np.sin(t * speed / 120.0) + 0.5 * t
    cy = 360 + 60 * np.sin(t * speed / 75.0)
    frames = []
    for i in range(n):
        f = bg.copy()
        x0 = int(round(cx[i])) - 45; y0 = int(round(cy[i])) - 63
        a = 1.0 if fade is None or i < fade else max(0.0, 1.0 - (i - fade) / 12.0)
        f[y0:y0 + 140, x0:x0 + 90] = plain + a * (cup - plain)
        if blur and i:
            v = int(round(abs(cx[i] - cx[i - 1]) / 2))
            if v > 0:
                k = np.ones(v + 1) / (v + 1)
                f[y0 - 5:y0 + 145] = np.apply_along_axis(lambda r: np.convolve(r, k, 'same'), 1, f[y0 - 5:y0 + 145])
        f = f * (1 + wobble / 255.0 * np.sin(i * 0.7)) + rng.normal(0, noise, f.shape)
        frames.append(np.clip(np.round(f), 0, 255).astype(np.uint8))
    return frames, np.stack([np.round(cx).astype(int), np.round(cy).astype(int)], 1)
