"""Relocate the archived TD sources into a new build tree; never runs TD."""
import argparse
from pathlib import Path
import shutil
import re

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / 'FPGA_two_boards_20261101'
MAPPINGS = {
    'G:/anlogic/HX1P35A_Contest_202606/work/fpga2_stereo_hdmi_rx_v1/CLAUDE_ZOOM_20261028/input30': 'upper_FPGA2_zoom30/project',
    'G:/anlogic/HX1P35A_Contest_202606/work/yolov5n_camera_ethernet_demo/sensor_sc520cs_v1/R10_TF_INTEGRATION': 'lower_FPGA1_CC24_PE16/project',
}
TEXT = {'.v', '.sv', '.vh', '.tcl', '.sdc', '.adc', '.py', '.sh', '.txt'}

def prepare(out):
    out = out.resolve()
    if out.exists():
        raise SystemExit('Output already exists. Choose a NEW directory; no overwrite is performed.')
    if out == SNAPSHOT or SNAPSHOT in out.parents:
        raise SystemExit('Output must be outside the frozen snapshot.')
    shutil.copytree(SNAPSHOT, out)
    changed = 0
    for f in out.rglob('*'):
        if not f.is_file() or f.suffix.lower() not in TEXT:
            continue
        original = data = f.read_bytes()
        for old, relative in MAPPINGS.items():
            data = data.replace(old.encode(), (out / relative).as_posix().encode())
        if data != original:
            f.write_bytes(data)
            changed += 1
    # Original lower-board orchestration copied DBs between stages. Make those
    # dependencies explicit in the BUILD COPY only, leaving options/SDC intact.
    lower = out / 'lower_FPGA1_CC24_PE16/project/cc24_perf_20261031/input4'
    for file, old, new in [
        ('phys1/placement.tcl', 'import_db camera_yolo_gate.db', 'import_db ../whole1/camera_yolo_gate.db'),
        ('bit1/bitgen.tcl', 'import_db own_final.db', 'import_db ../phys1/own_final.db'),
    ]:
        f = lower / file
        data = f.read_bytes()
        if data.count(old.encode()) != 1:
            raise SystemExit(f'Unexpected checkpoint import in {f}')
        f.write_bytes(data.replace(old.encode(), new.encode()))
    missing = []
    checked = 0
    for tcl in out.rglob('*.tcl'):
        for line in tcl.read_text().splitlines():
            if not line.startswith(('analyze ', 'read_adc ', 'read_ip_adc ', 'read_sdc ')):
                continue
            paths = re.findall(r'\{([^}]+\.(?:sv|v|vh|adc|sdc))\}', line)
            if not paths and line.startswith(('read_adc ', 'read_sdc ')):
                paths = [line.split()[1]]
            for name in paths:
                path = Path(name)
                if not path.is_absolute():
                    path = tcl.parent / path
                checked += 1
                if not path.is_file():
                    missing.append(str(path))
    print(f'Relocated {changed} text files; checked {checked} TD source/constraint references.')
    if missing:
        raise SystemExit('Missing inputs:\n' + '\n'.join(missing))
    for name in ('cc9_tone_lut.hex', 'fat_program3.hex', 'flash_model_header.hex', 'numeric_context1.hex'):
        if not (lower / 'whole1' / name).is_file():
            raise SystemExit(f'Missing lower ROM {name}')
    print(f'Prepared: {out}\nNo synthesis, programming, or motor commands were executed.')
    print('See docs/BUILD.md for sequential TD stages and fresh signoff requirements.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    prepare(parser.parse_args().output)
