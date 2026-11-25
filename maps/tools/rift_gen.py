"""Generates maps/rift.json (blue half, "mirror": "rotate") and a full-map preview PNG.

Coordinates: Godot (y down), 14800 x 14800, blue base bottom-left, red top-right.
The red half is the 180-degree rotation R(p) = (W - x, W - y).
"""
import json
import math
import sys
from PIL import Image, ImageDraw

W = 14800
OUT_JSON = sys.argv[1] if len(sys.argv) > 1 else "rift.json"
OUT_PNG = sys.argv[2] if len(sys.argv) > 2 else "rift_preview.png"


def R(p):
    return (W - p[0], W - p[1])


def D(p):
    """Reflection across the mid-lane diagonal (x + y = W) - blue top side <-> blue bot side."""
    return (W - p[1], W - p[0])


def ellipse(cx, cy, rx, ry, n=10, rot=0.0):
    pts = []
    for i in range(n):
        a = math.tau * i / n
        x, y = math.cos(a) * rx, math.sin(a) * ry
        c, s = math.cos(rot), math.sin(rot)
        pts.append((cx + x * c - y * s, cy + x * s + y * c))
    return pts


def arc_wall(cx, cy, r_in, r_out, a0, a1, n=14):
    """Thick arc (degrees, Godot angles: 0 = +x, 90 = +y/down)."""
    outer, inner = [], []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        outer.append((cx + math.cos(a) * r_out, cy + math.sin(a) * r_out))
        inner.append((cx + math.cos(a) * r_in, cy + math.sin(a) * r_in))
    return outer + inner[::-1]


def rnd(poly):
    return [[int(round(x)), int(round(y))] for x, y in poly]


# ------------------------------------------------------------------ lanes ---
TOP = [(1350, 12650), (1220, 11000), (1220, 9500), (1220, 4200), (1400, 2200),
       (2200, 1400), (4200, 1220), (9500, 1220), (11000, 1220), (12650, 1350)]
MID = [(2000, 12800), (3300, 11500), (7400, 7400), (11500, 3300), (12800, 2000)]
BOT = [R(p) for p in reversed(TOP)]
LANES = [TOP, MID, BOT]

# ------------------------------------------------------------- structures ---
SPAWN = (560, 14240)
NEXUS = (1540, 13250)
SHOP = (330, 13580)
TOWERS = [
    {"lane": 0, "order": 0, "pos": (970, 4420)},
    {"lane": 0, "order": 1, "pos": (1500, 8160)},
    {"lane": 0, "order": 2, "pos": (1160, 10570)},
    {"lane": 0, "order": 3, "kind": "inhibitor", "pos": (1160, 11290)},
    {"lane": 1, "order": 0, "pos": (5950, 8550)},
    {"lane": 1, "order": 1, "pos": (5040, 10050)},
    {"lane": 1, "order": 2, "pos": (3640, 11160)},
    {"lane": 1, "order": 3, "kind": "inhibitor", "pos": (3190, 11650)},
    {"lane": 2, "order": 0, "pos": (10500, 13830)},
    {"lane": 2, "order": 1, "pos": (6910, 13380)},
    {"lane": 2, "order": 2, "pos": (4280, 13600)},
    {"lane": 2, "order": 3, "kind": "inhibitor", "pos": (3440, 13620)},
    {"lane": -1, "kind": "nexus_turret", "pos": (1760, 12620)},
    {"lane": -1, "kind": "nexus_turret", "pos": (2180, 13040)},
]

# ------------------------------------------------------------------ river ---
def river_half():
    widths = [(1650, 430), (2600, 640), (4000, 760), (5200, 820), (6300, 680), (7400, 600)]
    n = (math.sqrt(0.5), -math.sqrt(0.5))
    blue_bank, red_bank = [], []
    for s, w in widths:
        o = -180.0 * math.sin(math.pi * (s - 1650) / (7400 - 1650))
        c = (s + n[0] * o, s + n[1] * o)
        blue_bank.append((c[0] - n[0] * w, c[1] - n[1] * w))
        red_bank.append((c[0] + n[0] * w, c[1] + n[1] * w))
    return blue_bank + red_bank[::-1]

RIVER = [river_half()]

# ------------------------------------------------------------------ brush ---
BRUSH = [
    ellipse(1520, 3050, 170, 400, 10),            # top lane, blue side of the river
    ellipse(11750, 13230, 400, 170, 10),          # bot lane, blue side of the river
    [(9850, 12050), (10450, 11950), (10200, 12600)],  # blue tri-brush (bot lane -> Red / river)
    ellipse(2250, 9260, 260, 170, 10),            # top-side jungle entrance by the wolves
    ellipse(11420, 11700, 240, 170, 10, 0.8),     # bot river "pixel" brush
    ellipse(6250, 7880, 170, 320, 10, 0.785),     # mid lane brush (top side)
    ellipse(7000, 8560, 170, 320, 10, 0.785),     # mid lane brush (bot side)
    ellipse(4800, 7000, 230, 160, 10, 0.2),       # by Blue Sentinel (toward mid)
    ellipse(4550, 8650, 250, 160, 10, 0.3),       # wolves -> mid path
    ellipse(8650, 9500, 240, 160, 10, 0.785),     # river entrance by the dragon pit
    ellipse(6380, 11050, 260, 180, 10),           # bot-side junction by the base
    ellipse(7800, 12850, 240, 160, 10, -0.5),     # krugs -> bot lane
    ellipse(6450, 9450, 220, 150, 10, -0.6),      # raptors -> mid
    ellipse(8240, 11800, 230, 160, 10, 0.6),      # red -> krugs
    ellipse(1950, 7000, 200, 150, 10, 0.6),       # gromp -> top lane
    ellipse(2350, 4750, 250, 160, 10),            # top lane entrance by the outer turret
]

# ------------------------------------------------------------------ walls ---
# Negative space: the jungle is solid rock, walkable lanes/river/base/paths/clearings are carved out.
from shapely.geometry import Polygon, LineString, Point, MultiPolygon
from shapely.ops import unary_union
from shapely import affinity


def Rg(g):
    return affinity.rotate(g, 180, origin=(W / 2, W / 2))


def Dg(g):
    # reflection across x + y = W: (x, y) -> (W - y, W - x)
    return affinity.affine_transform(g, [0, -1, -1, 0, W, W])


def path(pts, hw):
    return LineString(pts).buffer(hw, cap_style=1, join_style=1)


G = (2250, 6420)          # Gromp
B = (3800, 6760)          # Blue Sentinel
WF = (3750, 8420)         # Murk Wolves
RD = D(B)                 # Red Brambleback
K = D(G)                  # Krugs
RP = (6950, 9650)         # Raptors
DRAGON = (9860, 10440)

TOP_PATHS = [
    ([(1500, 4650), (2350, 4750), (3050, 5250), (3500, 5950), B], 240),   # top lane (outer turret) -> Blue
    ([B, (3000, 6560), G], 270),                                           # Blue -> Gromp
    ([G, (1950, 7000), (1550, 7300)], 190),                                # Gromp -> top lane (narrow)
    ([B, (4250, 6250), (4800, 5750)], 250),                                # Blue -> river (top scuttle)
    ([B, (3450, 7550), WF], 240),                                          # Blue -> Wolves
    ([WF, (4550, 8650), (5350, 8900)], 240),                               # Wolves -> mid lane
    ([WF, (2950, 9050), (2100, 9300), (1500, 9350)], 240),                 # Wolves -> top gate
    ([B, (4850, 7000), (5750, 7250), (6500, 7650)], 240),                  # Blue -> mid lane by the river
]
TOP_CLEAR = [(G, 400), (B, 470), (WF, 430)]
BOT_PATHS = [(list(map(D, pts)), hw) for pts, hw in TOP_PATHS[:3] + TOP_PATHS[6:]] + [
    ([RD, (8250, 10300), (8450, 9650)], 250),                              # Red -> river (north of the dragon pit)
    ([RD, (7500, 10250), RP], 240),                                        # Red -> Raptors
    ([RP, (6200, 9350)], 240),                                             # Raptors -> mid lane
    ([RP, (6650, 10450), D(WF)], 240),                                     # Raptors -> base-side junction
]
BOT_CLEAR = [(RD, 470), (K, 400), (RP, 430), (D(WF), 330)]


def carve():
    W2 = W
    half = Polygon([(0, 0), (W2, W2), (0, W2)])
    z1 = Polygon([(0, 0), (3000, 0), (0, 3000)])
    z2 = Rg(z1)
    lanes = unary_union([path(TOP, 450), path(MID, 430), path(BOT, 450)])
    river = unary_union([Polygon(p) for p in RIVER] + [Rg(Polygon(p)) for p in RIVER]).buffer(40)
    base_half = [(0, 10750), (1800, 10850), (2600, 10900), (3300, 11000), (3750, 11050)]
    base = Polygon([(0, W2)] + base_half + [D(p) for p in reversed(base_half[:-1])])
    jungle = []
    for pts, hw in TOP_PATHS + BOT_PATHS:
        jungle.append(path(pts, hw))
        for p in pts[1:-1]:
            jungle.append(Point(p).buffer(hw + 60))
    for c, r in TOP_CLEAR + BOT_CLEAR:
        jungle.append(Point(c).buffer(r))
    jungle += [Polygon(b).buffer(60) for b in BRUSH]
    blue_walk = unary_union(jungle + [base])
    walk = unary_union([lanes, river, blue_walk, Rg(blue_walk)])
    pit = Polygon(arc_wall(DRAGON[0], DRAGON[1], 640, 990, 10, 260, 40))
    pit_area = Point(DRAGON).buffer(950, 64)
    solid = half.difference(z1).difference(z2).difference(walk)
    solid = solid.difference(pit_area).difference(Rg(pit_area))
    solid = unary_union([solid, pit])
    corners = unary_union([z1, z2]).intersection(Polygon([(0, 0), (W2, 0), (W2, W2), (0, W2)])).difference(walk)
    return solid, corners


def polys(g, min_area=60000, tol=28):
    out = []
    geoms = g.geoms if hasattr(g, "geoms") else [g]
    for p in geoms:
        if p.area < min_area:
            continue
        p = p.simplify(tol, preserve_topology=True)
        if len(p.interiors) > 0:
            raise SystemExit("wall polygon with a hole near %s" % (p.interiors[0].coords[0],))
        out.append(list(p.exterior.coords)[:-1])
    return out


def split_walls(solid, corners):
    """Union both halves; polygons crossing the mirror diagonal are emitted whole ("mirror": false)."""
    full = unary_union([solid, Rg(solid), corners])
    mirrored, whole = [], []
    for p in polys(full):
        ys = [y - x for x, y in p]
        if min(ys) >= -1.0:
            mirrored.append(p)
        elif max(ys) > 1.0:
            whole.append(p)
    return mirrored, whole


SOLID, CORNERS = carve()
WALLS, CORNER_WALLS = split_walls(SOLID, CORNERS)

# ------------------------------------------------------------------ camps ---
CAMPS = [
    {"kind": "gromp", "pos": G},
    {"kind": "blue", "pos": B},
    {"kind": "wolves", "pos": WF},
    {"kind": "raptors", "pos": RP},
    {"kind": "red", "pos": RD},
    {"kind": "krugs", "pos": K},
    {"kind": "scuttle", "pos": (10410, 9540), "path": [(8500, 8800), (10410, 9540), (11700, 11250)]},
    {"kind": "dragon", "pos": DRAGON, "mirror": False},
    {"kind": "baron", "pos": R(DRAGON), "mirror": False},
]


def validate():
    full = unary_union([Polygon(p) for p in WALLS] + [Rg(Polygon(p)) for p in WALLS] + [Polygon(p) for p in CORNER_WALLS])
    for i, b in enumerate(BRUSH):
        bp = Polygon(b)
        f = bp.intersection(full).area / bp.area
        if f > 0.25:
            print("WARN brush %d at %s is %.0f%% inside walls" % (i, tuple(int(v) for v in bp.centroid.coords[0]), f * 100))
    for c in CAMPS:
        for p in [c["pos"]] + list(c.get("path", [])):
            if full.distance(Point(p)) < 200:
                print("WARN camp %s point %s is within 200 of a wall" % (c["kind"], p))
    for t in TOWERS:
        if full.distance(Point(t["pos"])) < 120:
            print("WARN tower %s too close to a wall" % (t["pos"],))
    verts = sum(len(p) for p in WALLS) * 2 + sum(len(p) for p in CORNER_WALLS)
    print("walls: %d mirrored + %d whole, %d vertices total" % (len(WALLS), len(CORNER_WALLS), verts))


def build_json():
    def pt(p):
        return [int(round(p[0])), int(round(p[1]))]

    towers = []
    for t in TOWERS:
        e = {"lane": t["lane"]}
        if "order" in t:
            e["order"] = t["order"]
        if "kind" in t:
            e["kind"] = t["kind"]
        e["pos"] = pt(t["pos"])
        towers.append(e)
    camps = []
    for c in CAMPS:
        e = {"kind": c["kind"], "pos": pt(c["pos"])}
        if "path" in c:
            e["path"] = [pt(p) for p in c["path"]]
        if c.get("mirror", True) is False:
            e["mirror"] = False
        camps.append(e)
    return {
        "name": "Aether Rift",
        "description": "Summoner's Rift-style: three lanes, a river, two jungles with buffs, Dragon, Baron, Scuttle and brush.",
        "size": [W, W],
        "mirror": "rotate",
        "spawn": pt(SPAWN),
        "nexus": pt(NEXUS),
        "shop": pt(SHOP),
        "fountain_radius": 700,
        "lane_width": 260,
        "waves": {"interval": 30, "first": 65, "melee": 3, "ranged": 3, "rift": True},
        "lane_order": [1, 0, 2, -1, 2],
        "lane_names": ["Top", "Mid", "Bot"],
        "lanes": [[pt(p) for p in l] for l in LANES],
        "towers": towers,
        "walls": [{"poly": rnd(p)} for p in WALLS] + [{"poly": rnd(p), "mirror": False} for p in CORNER_WALLS],
        "brush": [rnd(p) for p in BRUSH],
        "river": [rnd(p) for p in RIVER],
        "camps": camps,
    }


def write_json(d):
    # Compact one-line-per-entry formatting, readable and diff-friendly.
    lines = ["{"]
    keys = list(d.keys())
    for i, k in enumerate(keys):
        v = d[k]
        comma = "," if i < len(keys) - 1 else ""
        if isinstance(v, list) and v and isinstance(v[0], (dict, list)) and k != "size":
            lines.append(f'  "{k}": [')
            for j, e in enumerate(v):
                c2 = "," if j < len(v) - 1 else ""
                lines.append("    " + json.dumps(e, separators=(", ", ": ")) + c2)
            lines.append("  ]" + comma)
        else:
            lines.append(f'  "{k}": ' + json.dumps(v, separators=(", ", ": ")) + comma)
    lines.append("}")
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def preview(d):
    S = 0.07
    img = Image.new("RGB", (int(W * S), int(W * S)), (46, 74, 47))
    dr = ImageDraw.Draw(img)

    def P(p):
        return (p[0] * S, p[1] * S)

    def both(poly, mirror=True):
        out = [poly]
        if mirror:
            out.append([R(p) for p in poly])
        return out

    for poly in d["river"]:
        for q in both(poly):
            dr.polygon([P(p) for p in q], fill=(52, 92, 120))
    for l in d["lanes"]:
        dr.line([P(p) for p in l], fill=(110, 95, 69), width=int(2 * d["lane_width"] * S))
    for w in d["walls"]:
        for q in both(w["poly"], w.get("mirror", True)):
            dr.polygon([P(p) for p in q], fill=(74, 80, 92), outline=(30, 30, 36))
    for b in d["brush"]:
        for q in both(b):
            dr.polygon([P(p) for p in q], fill=(30, 110, 40), outline=(15, 60, 20))
    for t in (0, 1):
        sp = d["spawn"] if t == 0 else R(d["spawn"])
        col = (77, 141, 255) if t == 0 else (255, 90, 77)
        r = d["fountain_radius"] * S
        dr.ellipse([sp[0] * S - r, sp[1] * S - r, sp[0] * S + r, sp[1] * S + r], outline=col, width=2)
        nx = d["nexus"] if t == 0 else R(d["nexus"])
        dr.ellipse([nx[0] * S - 7, nx[1] * S - 7, nx[0] * S + 7, nx[1] * S + 7], fill=col)
        for tw in d["towers"]:
            p = tw["pos"] if t == 0 else R(tw["pos"])
            k = 4 if tw.get("kind") == "inhibitor" else 3
            if tw.get("kind") == "inhibitor":
                dr.ellipse([p[0] * S - k, p[1] * S - k, p[0] * S + k, p[1] * S + k], fill=col, outline=(0, 0, 0))
            else:
                dr.rectangle([p[0] * S - k, p[1] * S - k, p[0] * S + k, p[1] * S + k], fill=col, outline=(0, 0, 0))
    for c in d["camps"]:
        ps = [c["pos"]] if c.get("mirror", True) is False else [c["pos"], R(c["pos"])]
        for p in ps:
            big = c["kind"] in ("dragon", "baron")
            r = 7 if big else 4
            col = {"dragon": (255, 140, 40), "baron": (170, 60, 220), "scuttle": (120, 220, 255)}.get(c["kind"], (240, 220, 80))
            dr.ellipse([p[0] * S - r, p[1] * S - r, p[0] * S + r, p[1] * S + r], fill=col, outline=(0, 0, 0))
    img.save(OUT_PNG)


if __name__ == "__main__":
    validate()
    data = build_json()
    write_json(data)
    preview(data)
    print("wrote", OUT_JSON, OUT_PNG)
