"""Builds Sir Bonk's sprite sheets from this pack.

Every source sheet is 15 frames x 8 directions of 128x128 cells. Each animation used by
Sir Bonk is cropped to the smallest box (shared by all its frames and directions) that is
symmetric around the cell center, so the character's root stays at the center of every
cropped cell. The sheets go to characters/sir_bonk/knight/ (lossless WebP) and the cell
sizes are printed for characters/sir_bonk/character.json.

Run from anywhere:  python "2D HD Character Knight/build_sir_bonk.py"   (needs Pillow)
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "Spritesheets", "With shadows")
OUT = os.path.join(HERE, "..", "characters", "sir_bonk", "knight")
CELL, COLS, ROWS = 128, 15, 8

# source sheet -> output file
SHEETS = {
    "Idle": "idle", "Idle2": "idle2", "Walk": "walk", "Run": "run",
    "Melee": "melee", "Melee2": "melee2", "Pummel": "pummel",
    "MeleeRun": "melee_run", "ShieldBlockStart": "shield_block_start", "ShieldBlockMid": "shield_block_mid",
    "MeleeSpin": "melee_spin", "FrontFlip": "front_flip",
    "TakeDamage": "take_damage", "Special2": "special2", "UnSheathSword": "unsheath_sword", "Die": "die",
}


def symmetric_box(im):
    """Half extents (x, y) around the cell center that contain every visible pixel."""
    alpha = im.getchannel("A")
    hx = hy = 0
    c = CELL // 2
    for r in range(ROWS):
        for col in range(COLS):
            b = alpha.crop((col * CELL, r * CELL, col * CELL + CELL, r * CELL + CELL)).getbbox()
            if b:
                hx = max(hx, c - b[0], b[2] - c)
                hy = max(hy, c - b[1], b[3] - c)
    return hx, hy


def portrait(path):
    """Bust of the sword-raised salute (Special2) over a warm vignette, 2x pixels."""
    im = Image.open(os.path.join(SRC, "Special2.png")).convert("RGBA")
    row, col = 1, 6
    bust = im.crop((col * CELL + 37, row * CELL + 27, col * CELL + 85, row * CELL + 75)).resize((96, 96), Image.NEAREST)
    bg = Image.new("RGBA", (96, 96))
    px = bg.load()
    for y in range(96):
        for x in range(96):
            d = min(1.0, (((x - 52) ** 2 + (y - 40) ** 2) ** 0.5) / 70.0)
            k = (1.0 - d) ** 1.6
            px[x, y] = (int(22 + 150 * k), int(17 + 112 * k), int(12 + 62 * k), 255)
    bg.alpha_composite(bust)
    bg.save(path, optimize=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for src, dst in SHEETS.items():
        im = Image.open(os.path.join(SRC, src + ".png")).convert("RGBA")
        hx, hy = symmetric_box(im)
        w, h = hx * 2, hy * 2
        c = CELL // 2
        sheet = Image.new("RGBA", (w * COLS, h * ROWS), (0, 0, 0, 0))
        for r in range(ROWS):
            for col in range(COLS):
                x0, y0 = col * CELL + c - hx, r * CELL + c - hy
                sheet.paste(im.crop((x0, y0, x0 + w, y0 + h)), (col * w, r * h))
        path = os.path.join(OUT, dst + ".webp")
        # Lossless WebP is under half the size of PNG (characters are sent to every client).
        sheet.save(path, "WEBP", lossless=True, quality=100, method=6)
        size = os.path.getsize(path)
        total += size
        print('%-20s "frame_width": %d, "frame_height": %d   (%d KB)' % (dst, w, h, size // 1024))
    portrait(os.path.join(OUT, "..", "portrait.png"))
    print("total %.1f MB" % (total / 1048576.0))


if __name__ == "__main__":
    main()
