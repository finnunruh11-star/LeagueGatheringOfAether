"""Packs the rendered frames into sprite sheets and writes the sprite block of character.json.

    python clorinde_sheets.py <render_dir> <character_dir>

<render_dir> is what `blender -b -P clorinde_render.py -- clips <render_dir> all` produced (one
folder of <direction>_<frame>.png per clip plus manifest.json). Each clip becomes one webp sheet
(columns = frames, rows = the 8 directions), cropped to the clip's bounding box; its "anchor" is
where her feet are in the frame. The "sprite" block of <character_dir>/character.json is replaced
and portrait.png is made from <render_dir>/portrait_raw.png if present. Needs Pillow.
"""
import json
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PIL import Image

SCALE = 1.0             # in-game scale (the frames are rendered at the size they are shown)
GROUND = 49             # the engine's ground point is 0.75 x the champion radius (65) below the unit's origin
DIRS = 8
PAD = 2


def _variant_key(name):
    """"attack", "attack#slash", "attack@vigil#3": variants ("#...") of an animation become a list, in this order."""
    tail = name.split("#", 1)[1] if "#" in name else ""
    return (0, 0) if tail == "" else ((1, int(tail)) if tail.isdigit() else (1, 0))


def main(render_dir, char_dir):
    with open(os.path.join(render_dir, "manifest.json")) as fh:
        man = json.load(fh)
    ax, ay = man["anchor"]
    out_dir = os.path.join(char_dir, "sprites")
    os.makedirs(out_dir, exist_ok=True)
    anims = {}
    top = 0
    for c in sorted(man["clips"], key=lambda c: (c["name"].split("#")[0], _variant_key(c["name"]))):
        src = os.path.join(render_dir, c["dir"])
        n = c["frames"]
        frames = [[Image.open(os.path.join(src, f"{d}_{f:02d}.png")) for f in range(n)] for d in range(DIRS)]
        box = None
        for row in frames:
            for im in row:
                b = im.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox()
                if b:
                    box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
        x0, y0 = max(box[0] - PAD, 0), max(box[1] - PAD, 0)
        x1, y1 = min(box[2] + PAD, frames[0][0].width), min(box[3] + PAD, frames[0][0].height)
        w, h = x1 - x0, y1 - y0
        sheet = Image.new("RGBA", (w * n, h * DIRS), (0, 0, 0, 0))
        for d, row in enumerate(frames):
            for f, im in enumerate(row):
                sheet.paste(im.crop((x0, y0, x1, y1)), (f * w, d * h))
        file = c["name"].replace("@", "_").replace("#", "_") + ".webp"
        sheet.save(os.path.join(out_dir, file), "WEBP", quality=78, alpha_quality=65, method=6)
        a = {"sheet": "sprites/" + file, "frame_width": w, "frame_height": h, "frames": n, "fps": c["fps"],
             "anchor": [round(ax - x0, 1), round(ay - y0, 1)]}
        if c.get("hit") is not None:
            a["hit"] = c["hit"]
        if c.get("land") is not None:
            a["land"] = c["land"]
        if c.get("stride"):
            a["speed"] = round(c["stride"] * man["px_per_m"] * SCALE * c["fps"] / n)
        a.update(c.get("extra") or {})
        name = c["name"]
        base = name.split("#")[0]
        if "#" in name:
            if not isinstance(anims.get(base), list):
                anims[base] = [anims[base]] if base in anims else []
            anims[base].append(a)
        else:
            anims[name] = a
        if name == "idle":
            top = round(ay - y0 - (min(im.getbbox()[1] for row in frames for im in row) - y0))
        print(f"{name}: {w}x{h} x {n} frames -> {file} ({os.path.getsize(os.path.join(out_dir, file)) // 1024} KB)")
    order = ["idle", "run", "attack", "cast_q", "cast_w", "cast_e", "cast_e_recast", "cast_r", "hurt", "stun", "death", "spawn",
             "recall", "fidget", "idle@vigil", "run@vigil", "attack@vigil", "cast_q@vigil", "cast_w@vigil", "cast_r@vigil", "hurt@vigil",
             "exit@vigil"]
    anims = {k: anims[k] for k in sorted(anims, key=lambda k: order.index(k) if k in order else 99)}
    spec = {"directions": DIRS, "scale": SCALE, "offset": [0, GROUND], "top": top, "blend": 0.1, "filter": "linear", "shadow": False,
            "animations": anims}
    with open(os.path.join(render_dir, "sprite.json"), "w") as fh:
        json.dump(spec, fh, indent=1)
    import set_sprite_json
    set_sprite_json.main(os.path.join(render_dir, "sprite.json"), os.path.join(char_dir, "character.json"))
    raw = os.path.join(render_dir, "portrait_raw.png")
    if os.path.exists(raw):
        make_portrait(raw, os.path.join(char_dir, "portrait.png"))


def make_portrait(raw, out, size=128):
    """Bust render over a dark violet radial gradient."""
    im = Image.open(raw).convert("RGBA")
    n = im.width
    bg = Image.new("RGBA", (n, n))
    px = bg.load()
    for y in range(n):
        for x in range(n):
            d = min(((x - n * 0.5) ** 2 + (y - n * 0.42) ** 2) ** 0.5 / (n * 0.7), 1.0)
            px[x, y] = (int(74 - 60 * d), int(58 - 48 * d), int(118 - 94 * d), 255)
    bg.alpha_composite(im)
    bg.resize((size, size), Image.LANCZOS).save(out)
    print("portrait ->", out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
