#!/usr/bin/env python3
"""Builds PRIME/Resources/anatomy.json (and an SVG preview) from point outlines.

Shapes are authored for the viewer's left half of a 200 x 440 figure and mirrored.
Outlines are smoothed with a closed Catmull-Rom spline and written as absolute
M/C/Z path commands, which is all the Swift parser needs to understand.
"""
import json
import sys
from pathlib import Path

W, H = 200, 440


def smooth(points, tension=1.0):
    n = len(points)
    out = [f"M{points[0][0]:.1f},{points[0][1]:.1f}"]
    for i in range(n):
        p0, p1, p2, p3 = points[i - 1], points[i], points[(i + 1) % n], points[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6 * tension, p1[1] + (p2[1] - p0[1]) / 6 * tension)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6 * tension, p2[1] - (p3[1] - p1[1]) / 6 * tension)
        out.append(f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}")
    out.append("Z")
    return " ".join(out)


def mirror(points):
    return [(W - x, y) for x, y in reversed(points)]


def ellipse(cx, cy, rx, ry, n=16):
    import math
    return [(cx + rx * math.cos(2 * math.pi * k / n), cy + ry * math.sin(2 * math.pi * k / n)) for k in range(n)]


def pair(points):
    return [smooth(points), smooth(mirror(points))]


# ---------------------------------------------------------------- silhouette
head = ellipse(100, 33, 16.5, 21)
neck = [(90, 48), (110, 48), (113, 66), (100, 70), (87, 66)]
torso_half = [(100, 63), (86, 64), (70, 69), (58, 76), (53, 88), (57, 104), (61, 124), (64, 146),
              (66, 166), (65, 186), (62, 204), (66, 216), (84, 224), (100, 228)]
torso = torso_half + [(W - x, y) for x, y in reversed(torso_half[1:-1])]
upper_arm = [(56, 76), (45, 84), (42, 102), (40, 124), (39, 146), (42, 156), (52, 157), (56, 140), (58, 120), (60, 104), (61, 88)]
forearm = [(40, 152), (35, 170), (31, 192), (30, 212), (37, 216), (42, 214), (47, 196), (52, 176), (54, 158), (47, 152)]
hand = [(30, 210), (27, 224), (28, 238), (33, 246), (38, 244), (41, 232), (42, 216), (36, 212)]
thigh = [(63, 200), (62, 228), (62, 258), (66, 288), (70, 308), (86, 310), (89, 288), (94, 262), (98, 236), (98, 224), (80, 214)]
shin = [(70, 300), (66, 322), (67, 346), (72, 376), (75, 398), (83, 400), (85, 376), (88, 346), (89, 322), (87, 300)]
foot = [(74, 394), (69, 408), (70, 416), (80, 418), (89, 416), (87, 404), (84, 394)]

base = [smooth(head), smooth(neck), smooth(torso)]
for part in (upper_arm, forearm, hand, thigh, shin, foot):
    base += pair(part)

# ---------------------------------------------------------------- front muscles
front = []


def add(view, muscle, points):
    for i, d in enumerate(pair(points)):
        view.append({"id": f"{muscle}-{'r' if i == 0 else 'l'}-{len(view)}", "muscle": muscle, "d": d})


add(front, "back", [(91, 60), (84, 65), (72, 70), (80, 72), (90, 70)])                      # upper traps
add(front, "shoulders", [(70, 70), (58, 74), (48, 82), (44, 96), (47, 110), (53, 106), (58, 94), (63, 84), (70, 78)])
add(front, "chest", [(97, 78), (97, 104), (88, 112), (75, 110), (64, 101), (62, 89), (70, 80), (84, 76)])
add(front, "biceps", [(55, 108), (48, 116), (44, 130), (44, 144), (48, 152), (54, 146), (57, 130), (58, 116)])
add(front, "forearms", [(43, 156), (38, 172), (34, 192), (34, 207), (40, 208), (45, 192), (50, 174), (52, 159), (48, 155)])
add(front, "abdominals", [(88, 114), (97.5, 113), (97.5, 198), (93, 203), (89, 188), (87, 150)])   # rectus
add(front, "abdominals", [(67, 122), (77, 124), (83, 148), (84, 180), (80, 192), (72, 178), (67, 156), (65, 136)])  # obliques
add(front, "quadriceps", [(66, 214), (79, 220), (91, 234), (92, 260), (88, 288), (82, 302), (74, 300), (68, 282), (65, 256), (64, 232)])
add(front, "calves", [(83, 314), (88, 332), (86, 356), (81, 370), (77, 350), (77, 328)])

front_detail = []
for y in (134, 152, 170):
    front_detail.append(f"M88.5,{y} L97.5,{y}")
    front_detail.append(f"M102.5,{y} L111.5,{y}")
front_detail.append("M100,80 L100,200")
front_detail += [f"M{x1},{y1} C{x2},{y2} {x3},{y3} {x4},{y4}" for x1, y1, x2, y2, x3, y3, x4, y4 in [
    (79, 222, 76, 250, 75, 275, 78, 298),
    (121, 222, 124, 250, 125, 275, 122, 298),
]]

# ---------------------------------------------------------------- back muscles
back = []
add(back, "back", [(100, 56), (88, 62), (70, 71), (80, 80), (90, 98), (99, 126)])            # traps
add(back, "shoulders", [(68, 71), (57, 75), (48, 84), (45, 98), (50, 104), (56, 96), (62, 86)])        # rear delts
add(back, "back", [(66, 100), (82, 104), (93, 124), (95, 146), (88, 158), (77, 158), (69, 142), (63, 120), (62, 106)])  # lats
add(back, "lowerBack", [(91, 150), (98, 146), (98, 196), (91, 198), (87, 178), (88, 160)])
add(back, "triceps", [(49, 104), (44, 118), (42, 136), (44, 150), (49, 152), (54, 140), (56, 122), (56, 106)])
add(back, "forearms", [(43, 156), (38, 172), (34, 192), (34, 207), (40, 208), (45, 192), (50, 174), (52, 159), (48, 155)])
add(back, "glutes", [(66, 200), (82, 198), (97, 206), (98, 232), (90, 246), (76, 248), (66, 236), (63, 218)])
add(back, "hamstrings", [(66, 250), (80, 250), (94, 254), (93, 282), (88, 302), (80, 305), (72, 300), (66, 278)])
add(back, "calves", [(69, 312), (78, 308), (86, 316), (87, 340), (82, 362), (75, 363), (70, 346), (67, 328)])

back_detail = ["M100,128 L100,198"]


def main(out_dir: Path, preview: Path | None):
    data = {
        "width": W, "height": H,
        "base": base,
        "front": front, "back": back,
        "frontDetail": front_detail, "backDetail": back_detail,
    }
    (out_dir / "anatomy.json").write_text(json.dumps(data, separators=(",", ":")))
    if preview:
        colours = {"chest": "#C8FF3C", "shoulders": "#8fd0ff", "biceps": "#ff9c66", "forearms": "#b79cff",
                   "abdominals": "#ff6fa8", "quadriceps": "#5ce1c6", "calves": "#f2c94c", "back": "#C8FF3C",
                   "lowerBack": "#ff6fa8", "triceps": "#ff9c66", "glutes": "#b79cff", "hamstrings": "#5ce1c6"}
        parts = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {2*W+40} {H}" width="{(2*W+40)*2}" height="{H*2}">',
                 f'<rect width="100%" height="100%" fill="#050506"/>']
        for offset, shapes, detail in ((0, front, front_detail), (W + 40, back, back_detail)):
            parts.append(f'<g transform="translate({offset},0)">')
            parts += [f'<path d="{d}" fill="#24242a"/>' for d in base]
            parts += [f'<path d="{s["d"]}" fill="{colours[s["muscle"]]}" fill-opacity="0.85" stroke="#050506" stroke-width="1.2"/>' for s in shapes]
            parts += [f'<path d="{d}" fill="none" stroke="#050506" stroke-width="1.2" stroke-linecap="round"/>' for d in detail]
            parts.append('</g>')
        parts.append('</svg>')
        preview.write_text("\n".join(parts))


if __name__ == "__main__":
    out = Path(sys.argv[1])
    main(out, Path(sys.argv[2]) if len(sys.argv) > 2 else None)
