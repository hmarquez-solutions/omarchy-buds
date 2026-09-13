#!/usr/bin/python3 -I
"""Trace the Buds4 Pro cut-out into the outline the bar and panel draw.

    magick assets/buds4-pro-black-cutout.png -alpha extract -compress none pgm:- \
      | python3 tools/trace-icon.py > BudsOutline.js

Reads a plain (P2) PGM alpha mask on stdin, walks the outer edge of each bud,
simplifies it, and writes the pair as cubic Bezier paths normalised to a
width of 1.0, top-left at the origin. BudsIcon.qml scales them to size at
run time, so the stroke stays one crisp hairline at every icon size and
follows the shell foreground like any glyph.
"""
import json
import math
import sys

THRESHOLD = 128        # alpha at or above this is "bud"
MIN_COMPONENT = 2000   # pixels; drops stray specks in the cut-out
SMOOTH_PASSES = 5      # 1-2-1 passes that take the pixel staircase out
SIMPLIFY_EPS = 2.0     # Douglas-Peucker tolerance, in source pixels


def read_pgm(stream):
    tokens = stream.read().split()
    if tokens[0] != "P2":
        sys.exit("expected a plain P2 PGM (use -compress none)")
    w, h = int(tokens[1]), int(tokens[2])
    vals = list(map(int, tokens[4:4 + w * h]))
    return w, h, [vals[y * w:(y + 1) * w] for y in range(h)]


def components(mask, w, h):
    seen = [[0] * w for _ in range(h)]
    out = []
    for y in range(h):
        for x in range(w):
            if not mask[y][x] or seen[y][x]:
                continue
            stack, pts = [(x, y)], []
            seen[y][x] = 1
            while stack:
                cx, cy = stack.pop()
                pts.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and mask[ny][nx] and not seen[ny][nx]:
                        seen[ny][nx] = 1
                        stack.append((nx, ny))
            if len(pts) >= MIN_COMPONENT:
                out.append(pts)
    return out


def boundary(pixels):
    """Crack-follow the outer edge, keeping the filled side on the right."""
    filled = set(pixels)
    x, y = min(pixels, key=lambda p: (p[1], p[0]))
    d = 0  # 0 E, 1 S, 2 W, 3 N
    start = (x, y, d)
    poly = []
    while True:
        poly.append((x, y))
        if d == 0: x += 1
        elif d == 1: y += 1
        elif d == 2: x -= 1
        else: y -= 1
        if d == 0: right, left = (x, y), (x, y - 1)
        elif d == 1: right, left = (x - 1, y), (x, y)
        elif d == 2: right, left = (x - 1, y - 1), (x - 1, y)
        else: right, left = (x, y - 1), (x - 1, y - 1)
        if left in filled:
            d = (d - 1) % 4
        elif right not in filled:
            d = (d + 1) % 4
        if (x, y, d) == start:
            return poly


def smooth(points, passes):
    for _ in range(passes):
        n = len(points)
        points = [((points[i - 1][0] + 2 * points[i][0] + points[(i + 1) % n][0]) / 4,
                   (points[i - 1][1] + 2 * points[i][1] + points[(i + 1) % n][1]) / 4)
                  for i in range(n)]
    return points


def simplify(points, eps):
    def dist(p, a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        if dx == dy == 0:
            return math.hypot(p[0] - a[0], p[1] - a[1])
        t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy)))
        return math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy))

    def rec(pts):
        idx, dmax = 0, 0.0
        for i in range(1, len(pts) - 1):
            dd = dist(pts[i], pts[0], pts[-1])
            if dd > dmax:
                idx, dmax = i, dd
        if dmax > eps:
            return rec(pts[:idx + 1])[:-1] + rec(pts[idx:])
        return [pts[0], pts[-1]]

    far = max(range(len(points)),
              key=lambda i: math.hypot(points[i][0] - points[0][0], points[i][1] - points[0][1]))
    first = rec(points[:far + 1])
    second = rec(points[far:] + [points[0]])
    return first[:-1] + second[:-1]


def beziers(pts):
    """Catmull-Rom through every anchor, as cubic segments."""
    n = len(pts)
    for i in range(n):
        p0, p1, p2, p3 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        yield c1, c2, p2


def main():
    w, h, img = read_pgm(sys.stdin)
    mask = [[1 if v >= THRESHOLD else 0 for v in row] for row in img]
    outlines = [simplify(smooth(boundary(c), SMOOTH_PASSES), SIMPLIFY_EPS)
                for c in components(mask, w, h)]
    if len(outlines) != 2:
        sys.exit("expected two buds, traced %d shapes" % len(outlines))
    every = [p for o in outlines for p in o]
    minx, maxx = min(p[0] for p in every), max(p[0] for p in every)
    miny, maxy = min(p[1] for p in every), max(p[1] for p in every)
    width = maxx - minx
    aspect = (maxy - miny) / width

    def norm(p):
        return (round((p[0] - minx) / width, 4), round((p[1] - miny) / width, 4))

    # Left bud first, so BudsIcon can name them.
    outlines.sort(key=lambda o: min(p[0] for p in o))
    shapes = []
    for o in outlines:
        pts = [norm(p) for p in o]
        segs = [pts[0]]
        for c1, c2, p in beziers(pts):
            segs.append([round(c1[0], 4), round(c1[1], 4), round(c2[0], 4), round(c2[1], 4), p[0], p[1]])
        shapes.append(segs)

    out = sys.stdout
    out.write("// Generated by tools/trace-icon.py from assets/buds4-pro-black-cutout.png. Do not edit.\n")
    out.write("// Outline of the Galaxy Buds4 Pro pair, normalised to width 1.0 with the top-left at 0,0.\n")
    out.write("// Each shape is a start point followed by cubic segments [c1x, c1y, c2x, c2y, x, y].\n\n")
    out.write(".pragma library\n\n")
    out.write("var ASPECT = %.4f\n\n" % aspect)
    out.write("var SHAPES = [\n")
    for i, s in enumerate(shapes):
        out.write("  [\n    %s,\n" % json.dumps(list(s[0])))
        out.write(",\n".join("    " + json.dumps(seg) for seg in s[1:]))
        out.write("\n  ]%s\n" % ("," if i == 0 else ""))
    out.write("]\n\n")
    out.write("""// SVG path data for one bud, scaled to `size` pixels wide and offset by dx, dy.
function svgPath(index, size, dx, dy) {
  var shape = SHAPES[index]
  if (!shape) return ""
  function px(v) { return (dx + v * size).toFixed(3) }
  function py(v) { return (dy + v * size).toFixed(3) }
  var d = "M " + px(shape[0][0]) + " " + py(shape[0][1])
  for (var i = 1; i < shape.length; i++) {
    var s = shape[i]
    d += " C " + px(s[0]) + " " + py(s[1]) + " " + px(s[2]) + " " + py(s[3]) + " " + px(s[4]) + " " + py(s[5])
  }
  return d + " Z"
}
""")


if __name__ == "__main__":
    main()
