#!/usr/bin/env python3
"""Builds PRIME/Resources/anatomy.json from the vendored anatomy artwork.

Source: tools/vendor/react-native-body-highlighter (MIT licence, see LICENSE there).
Every path is converted to absolute M/L/C/Z commands (arcs become cubic curves) so the
app's small path reader can draw it, then the front and back views are placed in a
shared frame so turning the body round keeps it the same size.

Run:  python3 tools/anatomy.py PRIME/Resources [preview-dir]
"""
import json
import math
import re
import sys
from pathlib import Path

VENDOR = Path(__file__).resolve().parent / "vendor" / "react-native-body-highlighter"

# Dataset region -> PRIME muscle id (None = drawn as body, not selectable).
REGION = {
    "chest": "chest", "abs": "abdominals", "obliques": "abdominals", "biceps": "biceps",
    "triceps": "triceps", "forearm": "forearms", "deltoids": "shoulders", "trapezius": "traps",
    "upper-back": "back", "lower-back": "lowerBack", "gluteal": "glutes", "hamstring": "hamstrings",
    "quadriceps": "quadriceps", "adductors": "adductors", "calves": "calves", "tibialis": "calves",
}
BODY_ONLY = {"head", "hair", "neck", "hands", "feet", "ankles", "knees"}

# Individual shapes that the dataset groups under a broader region.
OVERRIDES = {
    # Male back view: gluteus medius bands above glute max are the hip abductors;
    # the small flank shapes are the obliques seen from behind; the outer thigh
    # strips are vastus lateralis.
    ("male", "back"): {30: "abductors", 32: "abductors", 18: "abdominals", 21: "abdominals",
                       36: "quadriceps", 43: "quadriceps"},
    ("female", "back"): {42: "abductors", 45: "abductors", 12: "abdominals", 15: "abdominals",
                         50: "quadriceps", 55: "quadriceps"},
}

NUM = re.compile(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def tokenize(d):
    i, out = 0, []
    while i < len(d):
        c = d[i]
        if c.isalpha():
            out.append(c)
            i += 1
        elif c in " ,\n\t":
            i += 1
        else:
            m = NUM.match(d, i)
            if not m:
                raise ValueError(f"bad path near {d[i:i+20]!r}")
            out.append(float(m.group(0)))
            i = m.end()
    return out


def read_flag(tokens, idx, d_text_tokens):
    return tokens[idx]


def arc_to_cubics(x1, y1, rx, ry, phi, large, sweep, x2, y2):
    if x1 == x2 and y1 == y2:
        return []
    if rx == 0 or ry == 0:
        return [((x1, y1), (x2, y2), (x2, y2))]
    rx, ry = abs(rx), abs(ry)
    cp, sp = math.cos(math.radians(phi)), math.sin(math.radians(phi))
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    lam = (x1p ** 2) / (rx ** 2) + (y1p ** 2) / (ry ** 2)
    if lam > 1:
        s = math.sqrt(lam)
        rx, ry = rx * s, ry * s
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = math.sqrt(max(0, num / den)) if den else 0
    if large == sweep:
        coef = -coef
    cxp, cyp = coef * rx * y1p / ry, -coef * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    segs = max(1, math.ceil(abs(dt) / (math.pi / 2)))
    delta = dt / segs
    k = 4 / 3 * math.tan(delta / 4)
    out = []
    t = t1
    for _ in range(segs):
        c1, s1 = math.cos(t), math.sin(t)
        c2, s2 = math.cos(t + delta), math.sin(t + delta)
        p1 = (c1 - k * s1, s1 + k * c1)
        p2 = (c2 + k * s2, s2 - k * c2)
        p3 = (c2, s2)

        def tf(p):
            x, y = p[0] * rx, p[1] * ry
            return (cp * x - sp * y + cx, sp * x + cp * y + cy)

        out.append((tf(p1), tf(p2), tf(p3)))
        t += delta
    return out


def parse_arc_args(d, pos):
    """Arc args: rx ry rot flag flag x y, where flags may be packed like '012.5'."""
    vals = []
    i = pos
    count = 0
    while count < 7:
        while i < len(d) and d[i] in " ,\n\t":
            i += 1
        if count in (3, 4):
            vals.append(float(d[i]))
            i += 1
        else:
            m = NUM.match(d, i)
            vals.append(float(m.group(0)))
            i = m.end()
        count += 1
    return vals, i


def to_absolute(d):
    """Returns a list of commands ('M', x, y) / ('L', x, y) / ('C', x1, y1, x2, y2, x, y) / ('Z',)."""
    out = []
    i = 0
    cmd = None
    cx = cy = sx = sy = 0.0
    last_ctrl = None
    last_q = None

    def number():
        nonlocal i
        while i < len(d) and d[i] in " ,\n\t":
            i += 1
        m = NUM.match(d, i)
        if not m:
            return None
        i = m.end()
        return float(m.group(0))

    while i < len(d):
        while i < len(d) and d[i] in " ,\n\t":
            i += 1
        if i >= len(d):
            break
        if d[i].isalpha():
            cmd = d[i]
            i += 1
            if cmd in "Zz":
                out.append(("Z",))
                cx, cy = sx, sy
                last_ctrl = last_q = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            x, y = number(), number()
            if rel:
                x, y = cx + x, cy + y
            out.append(("M", x, y))
            cx, cy, sx, sy = x, y, x, y
            cmd = "l" if rel else "L"
            last_ctrl = last_q = None
        elif c == "L":
            x, y = number(), number()
            if rel:
                x, y = cx + x, cy + y
            out.append(("L", x, y))
            cx, cy = x, y
            last_ctrl = last_q = None
        elif c == "H":
            x = number()
            x = cx + x if rel else x
            out.append(("L", x, cy))
            cx = x
            last_ctrl = last_q = None
        elif c == "V":
            y = number()
            y = cy + y if rel else y
            out.append(("L", cx, y))
            cy = y
            last_ctrl = last_q = None
        elif c == "C":
            v = [number() for _ in range(6)]
            if rel:
                v = [v[0] + cx, v[1] + cy, v[2] + cx, v[3] + cy, v[4] + cx, v[5] + cy]
            out.append(("C", *v))
            last_ctrl = (v[2], v[3])
            last_q = None
            cx, cy = v[4], v[5]
        elif c == "S":
            v = [number() for _ in range(4)]
            if rel:
                v = [v[0] + cx, v[1] + cy, v[2] + cx, v[3] + cy]
            c1 = (2 * cx - last_ctrl[0], 2 * cy - last_ctrl[1]) if last_ctrl else (cx, cy)
            out.append(("C", c1[0], c1[1], v[0], v[1], v[2], v[3]))
            last_ctrl = (v[0], v[1])
            last_q = None
            cx, cy = v[2], v[3]
        elif c in "QT":
            if c == "Q":
                v = [number() for _ in range(4)]
                if rel:
                    v = [v[0] + cx, v[1] + cy, v[2] + cx, v[3] + cy]
                q = (v[0], v[1])
                end = (v[2], v[3])
            else:
                v = [number() for _ in range(2)]
                if rel:
                    v = [v[0] + cx, v[1] + cy]
                q = (2 * cx - last_q[0], 2 * cy - last_q[1]) if last_q else (cx, cy)
                end = (v[0], v[1])
            c1 = (cx + 2 / 3 * (q[0] - cx), cy + 2 / 3 * (q[1] - cy))
            c2 = (end[0] + 2 / 3 * (q[0] - end[0]), end[1] + 2 / 3 * (q[1] - end[1]))
            out.append(("C", c1[0], c1[1], c2[0], c2[1], end[0], end[1]))
            last_q = q
            last_ctrl = None
            cx, cy = end
        elif c == "A":
            (rx, ry, rot, large, sweep, x, y), i = parse_arc_args(d, i)
            if rel:
                x, y = cx + x, cy + y
            for c1, c2, p in arc_to_cubics(cx, cy, rx, ry, rot, int(large), int(sweep), x, y):
                out.append(("C", c1[0], c1[1], c2[0], c2[1], p[0], p[1]))
            cx, cy = x, y
            last_ctrl = last_q = None
        else:
            raise ValueError(f"unsupported command {cmd}")
    return out


def bounds(cmds):
    xs, ys = [], []
    for c in cmds:
        if c[0] != "Z":
            xs += c[1::2]
            ys += c[2::2]
    return min(xs), min(ys), max(xs), max(ys)


def emit(cmds, dx, dy):
    parts = []
    for c in cmds:
        if c[0] == "Z":
            parts.append("Z")
        else:
            pts = " ".join(f"{c[k] + dx:.1f},{c[k + 1] + dy:.1f}" for k in range(1, len(c), 2))
            parts.append(f"{c[0]}{pts}")
    return " ".join(parts)


def parse_ts(path):
    s = path.read_text()
    out = []
    for block in re.split(r"\n\s*\{\s*\n\s*slug:", s)[1:]:
        slug = re.match(r'\s*"([a-z-]+)"', block).group(1)
        for side in ("left", "right", "common"):
            m = re.search(side + r":\s*\[(.*?)\]", block, re.S)
            if m:
                for d in re.findall(r'"([^"]+)"', m.group(1)):
                    out.append((slug, d))
    return out


def build_figure(sex, front_file, back_file):
    views = {}
    allb = []
    for view, fn in (("front", front_file), ("back", back_file)):
        items = []
        for index, (slug, d) in enumerate(parse_ts(VENDOR / fn)):
            cmds = to_absolute(d)
            muscle = OVERRIDES.get((sex, view), {}).get(index, REGION.get(slug))
            if slug not in BODY_ONLY and muscle is None:
                raise SystemExit(f"unmapped region {slug}")
            items.append((muscle if slug not in BODY_ONLY else None, cmds))
        b = [bounds(c) for _, c in items]
        box = (min(x[0] for x in b), min(x[1] for x in b), max(x[2] for x in b), max(x[3] for x in b))
        views[view] = (items, box)
        allb.append(box)
    w = max(b[2] - b[0] for b in allb) + 24
    h = max(b[3] - b[1] for b in allb) + 24
    figure = {"width": round(w, 1), "height": round(h, 1)}
    for view, (items, box) in views.items():
        dx = (w - (box[2] - box[0])) / 2 - box[0]
        dy = (h - (box[3] - box[1])) / 2 - box[1]
        base, muscles = [], []
        for n, (muscle, cmds) in enumerate(items):
            d = emit(cmds, dx, dy)
            if muscle is None:
                base.append(d)
            else:
                muscles.append({"id": f"{view}-{n}", "muscle": muscle, "d": d})
        figure[view] = muscles
        figure[view + "Base"] = base
    return figure


def main(out_dir, preview_dir=None):
    data = {
        "credit": "Anatomy artwork adapted from react-native-body-highlighter by ELABBASSI Hicham (MIT licence).",
        "male": build_figure("male", "bodyFront.ts", "bodyBack.ts"),
        "female": build_figure("female", "bodyFemaleFront.ts", "bodyFemaleBack.ts"),
    }
    (Path(out_dir) / "anatomy.json").write_text(json.dumps(data, separators=(",", ":")))
    counts = {sex: {v: len(data[sex][v]) for v in ("front", "back")} for sex in ("male", "female")}
    print("anatomy.json written", counts, f"{(Path(out_dir) / 'anatomy.json').stat().st_size // 1024} KB")
    if preview_dir:
        colours = {"chest": "#397BFF", "abdominals": "#69B7FF", "shoulders": "#ff9c66", "biceps": "#c08bff",
                   "triceps": "#a070ff", "forearms": "#5ce1c6", "quadriceps": "#f2c94c", "adductors": "#ff6fa8",
                   "abductors": "#ff3b6b", "calves": "#f2994a", "traps": "#4fd1ff", "back": "#397BFF",
                   "lowerBack": "#ff6fa8", "glutes": "#c08bff", "hamstrings": "#f2c94c"}
        for sex in ("male", "female"):
            fig = data[sex]
            w, h = fig["width"], fig["height"]
            parts = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {2 * w + 40} {h}" width="{(2 * w + 40) / 2}" height="{h / 2}">',
                     '<rect width="100%" height="100%" fill="#05070B"/>']
            for k, view in enumerate(("front", "back")):
                parts.append(f'<g transform="translate({k * (w + 40)},0)">')
                parts += [f'<path d="{d}" fill="#1B2638"/>' for d in fig[view + "Base"]]
                parts += [f'<path d="{s["d"]}" fill="{colours[s["muscle"]]}" stroke="#05070B" stroke-width="2"/>' for s in fig[view]]
                parts.append("</g>")
            parts.append("</svg>")
            (Path(preview_dir) / f"anatomy-{sex}.svg").write_text("\n".join(parts))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
