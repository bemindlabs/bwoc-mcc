#!/usr/bin/env python3
"""Slice the BWOC mascot 8-view turnaround contact-sheet into a clean,
transparent horizontal sprite atlas (8 frames, uniform cell) for the
floating desktop mascot. Run from anywhere:

    python3 scripts/gen-mascot-sheet.py [SOURCE_PNG]

Source defaults to the brand asset in bwoc-series. Output is committed at
Sources/BwocMcc/Resources/mascot_sheet.png so the build needs no external asset.
"""
import sys, os
from collections import deque
from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    HERE, "..", "bwoc-series", "assets", "brand", "mascot_turnaround.png")
OUT = os.path.join(HERE, "Sources", "BwocMcc", "Resources", "mascot_sheet.png")

# Contact-sheet grid (measured from the box border lines): 4 cols x 2 rows.
# COLS/ROWS are inner art spans, already inside the rounded cell borders and
# above each cell's angle-label strip. Order = 0,45,90,...,315 degrees.
COLS = [(35, 387), (415, 778), (804, 1178), (1204, 1562)]
ROWS = [(80, 398), (514, 820)]

def keyed_alpha(cell):
    """White cell background -> transparent, via flood fill from the border so
    white highlights inside the mascot are preserved."""
    cell = cell.convert("RGBA")
    w, h = cell.size
    px = cell.load()
    def removable(p):
        r, g, b, _ = p
        # The white cell background...
        if r > 238 and g > 238 and b > 238:
            return True
        # ...and the saturated magenta rounded-cell border line (much more
        # saturated than the mascot's soft pink: low green, no blue dominance),
        # so its corner arcs flood away from the edge without touching the body.
        if r > 210 and g < 95 and 70 < b < 185:
            return True
        return False
    seen = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y))
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y][x]:
            continue
        seen[y][x] = True
        if not removable(px[x, y]):
            continue
        px[x, y] = (0, 0, 0, 0)
        q.extend(((x+1, y), (x-1, y), (x, y+1), (x, y-1)))
    return cell

def main():
    im = Image.open(SRC).convert("RGB")
    frames = []
    for (y0, y1) in ROWS:
        for (x0, x1) in COLS:
            cell = im.crop((x0, y0, x1, y1))
            a = keyed_alpha(cell)
            frames.append(a.crop(a.getbbox()))  # trim to the mascot
    fw = max(f.width for f in frames)
    fh = max(f.height for f in frames)
    pad = 4
    fw += pad * 2; fh += pad * 2
    sheet = Image.new("RGBA", (fw * len(frames), fh), (0, 0, 0, 0))
    for idx, f in enumerate(frames):
        ox = idx * fw + (fw - f.width) // 2
        oy = fh - pad - f.height  # feet aligned to a common baseline
        sheet.paste(f, (ox, oy), f)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.save(OUT)
    print(f"wrote {OUT}  frames={len(frames)} cell={fw}x{fh} total={sheet.size}")

if __name__ == "__main__":
    main()
