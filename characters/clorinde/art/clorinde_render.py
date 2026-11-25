"""Scene setup (camera, light, ground shadow) and sprite rendering for Clorinde.

    blender -b -P clorinde_render.py -- preview <out_dir>       rest pose, 8 directions + face close-ups
    blender -b -P clorinde_render.py -- clips <out_dir> <all|name,name> [directions] [samples]
                                                                render clips to <out_dir>/<clip>/<dir>_<frame>.png
    blender -b -P clorinde_render.py -- portrait <out_dir>/portrait_raw.png
then `python clorinde_sheets.py <out_dir> ..` packs the sheets, the portrait and the sprite JSON.
The model is in clorinde_model.py, the pose solver / cloth / effects in clorinde_anim.py and the
animations in clorinde_clips.py.
"""
import json
import math
import random
import os
import sys
import time

import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import clorinde_anim as A  # noqa: E402
import clorinde_model as model  # noqa: E402

FRAME_PX = 320
ORTHO = FRAME_PX / 74.667       # 74.667 px per meter; sheets are shown at scale 1.0
CAM_TARGET = Vector((0, 0, 0.85))
CAM_TILT = 48.0          # degrees from straight down (about 42 degrees above the ground)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = FRAME_PX
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.render.fps = 30
    try:
        sc.eevee.taa_render_samples = 16
    except AttributeError:
        pass
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.45, 0.45, 0.55, 1)
    bg.inputs[1].default_value = 0.6
    sc.world = world
    return sc


def setup_camera(sc):
    cam = bpy.data.cameras.new("Cam")
    cam.type = "ORTHO"
    cam.ortho_scale = ORTHO
    ob = bpy.data.objects.new("Cam", cam)
    sc.collection.objects.link(ob)
    t = math.radians(CAM_TILT)
    d = 10.0
    ob.location = CAM_TARGET + Vector((0, -math.sin(t) * d, math.cos(t) * d))
    ob.rotation_euler = (t, 0, 0)
    sc.camera = ob
    # key light for the toon shading (no cast shadows), from the front left
    key = bpy.data.lights.new("Key", "SUN")
    key.energy = 3.0
    key.use_shadow = False
    ko = bpy.data.objects.new("Key", key)
    sc.collection.objects.link(ko)
    ko.rotation_euler = (math.radians(28), 0, math.radians(-35))
    # shadow light, only seen by the ground: from behind on the right, so the shadow falls down-left like the other champions'
    sun = bpy.data.lights.new("ShadowSun", "SUN")
    sun.energy = 3.0
    sun.angle = math.radians(4)
    so = bpy.data.objects.new("ShadowSun", sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(-18), 0, math.radians(-40))
    return ob


def setup_ground(sc):
    me = bpy.data.meshes.new("Ground")
    s = 3.0
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    ob = bpy.data.objects.new("Ground", me)
    sc.collection.objects.link(ob)
    m = bpy.data.materials.new("ShadowCatcher")
    m.use_nodes = True
    try:
        m.surface_render_method = "BLENDED"
    except AttributeError:
        m.blend_method = "BLEND"
    nt = m.node_tree
    nt.nodes.clear()
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    ramp = nt.nodes.new("ShaderNodeMapRange")       # lit ground -> 0 (transparent), shadowed -> 1
    ramp.inputs[1].default_value = 0.75
    ramp.inputs[2].default_value = 0.35
    ramp.inputs[3].default_value = 0.0
    ramp.inputs[4].default_value = 0.36
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (0.02, 0.01, 0.04, 1)
    mix = nt.nodes.new("ShaderNodeMixShader")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    lk = nt.links
    lk.new(dif.outputs[0], s2r.inputs[0])
    lk.new(s2r.outputs[0], bw.inputs[0])
    lk.new(bw.outputs[0], ramp.inputs[0])
    lk.new(ramp.outputs[0], mix.inputs[0])
    lk.new(tr.outputs[0], mix.inputs[1])
    lk.new(em.outputs[0], mix.inputs[2])
    lk.new(mix.outputs[0], out.inputs[0])
    me.materials.append(m)
    return ob


def build():
    sc = reset_scene()
    cam = setup_camera(sc)
    setup_ground(sc)
    rig, parts, weapons = model.build_all()
    ground = bpy.data.collections.new("GroundOnly")
    sc.collection.children.link(ground)
    g = bpy.data.objects["Ground"]
    for c in list(g.users_collection):
        c.objects.unlink(g)
    ground.objects.link(g)
    bpy.data.objects["Key"].light_linking.receiver_collection = model.COLLECTION
    bpy.data.objects["ShadowSun"].light_linking.receiver_collection = ground
    return sc, cam, rig, parts, weapons


def anchor_px(sc, cam):
    """Pixel of the world origin (the character's feet) in the frame."""
    from bpy_extras.object_utils import world_to_camera_view
    co = world_to_camera_view(sc, cam, Vector((0, 0, 0)))
    return round(co.x * FRAME_PX, 1), round((1 - co.y) * FRAME_PX, 1)


def render_to(sc, path):
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def set_direction(rig, d):
    """Row d of the sheet: 0 faces screen-right, then clockwise (1 = down-right, 2 = down ...)."""
    rig.rotation_euler = (0, 0, math.radians(-45 * d))


def preview(out_dir):
    sc, cam, rig, parts, weapons = build()
    for o in weapons["pistol"]:
        o.hide_render = True
    os.makedirs(out_dir, exist_ok=True)
    for d in range(8):
        set_direction(rig, d)
        render_to(sc, os.path.join(out_dir, f"dir{d}.png"))
    cam.data.ortho_scale = 0.75
    cam.location += Vector((0, 0, 1.62)) - CAM_TARGET
    for d in (1, 2, 3):
        set_direction(rig, d)
        render_to(sc, os.path.join(out_dir, f"face{d}.png"))
    set_direction(rig, 2)
    cam.rotation_euler = (math.radians(80), 0, 0)
    cam.location = Vector((0, -10 * math.sin(math.radians(80)), 1.62 + 10 * math.cos(math.radians(80))))
    render_to(sc, os.path.join(out_dir, "face_front.png"))
    print("ANCHOR", anchor_px(sc, cam))


def portrait(out_png):
    """HD bust (pistol raised by her cheek) for the lobby/HUD portrait; transparent, composited later."""
    import clorinde_clips as C
    sc, cam, rig, parts, weapons = build()
    sc.render.resolution_x = sc.render.resolution_y = 384
    sc.eevee.taa_render_samples = 32
    bpy.data.objects["Ground"].hide_render = True
    R = A.RigData(rig)
    p = A.pose(C.VREADY, handL=(0.16, 0.2, 1.5), aimL=(0.12, -0.05, 1.0), elbowL=(0.2, 1, -0.6), head=(18, -4, 4), neck=(10, 0, 0))
    sim = A.Sim(R)
    M = A.solve(R, p)
    for _ in range(200):
        sim.step(M, 1 / 160, (0, 0, 0))
    sim.apply(M)
    for name, m in A.to_basis(R, M).items():
        rig.pose.bones[name].matrix_basis = m
    for o in weapons["pistol"]:
        o.hide_render = False
    for o in weapons["holster"]:
        o.hide_render = True
    rig.rotation_euler = (0, 0, math.radians(-62))
    t = math.radians(74)
    target = Vector((0.03, 0, 1.56))
    cam.rotation_euler = (t, 0, 0)
    cam.location = target + Vector((0, -10 * math.sin(t), 10 * math.cos(t)))
    cam.data.ortho_scale = 0.78
    render_to(sc, out_png)


# ------------------------------------------------------------------------- baking clips ---

SUB = 8                 # simulation substeps per frame
TRAIL_LEN = 2.2         # frames of sword trail kept


def bake(R, clip, weapons):
    """Per frame: (pose bases, armature-space matrices, pistol flag, trail samples, fx names)."""
    sim = A.Sim(R)
    loop_len = clip.frames if clip.loop else None
    dt = 1.0 / (clip.fps * SUB)

    def at(t):
        p = A.sample(clip.keys, t, loop_len)
        return A.solve(R, p), p
    if clip.pre is not None:
        # settle the cloth in the previous pose, then snap into the first key over two frames so it whips along
        M = A.solve(R, clip.pre)
        for _ in range(SUB * 8):
            sim.step(M, dt, clip.pre["wind"])
        p0 = A.sample(clip.keys, 0.0)
        n = SUB * 2
        for k in range(n):
            u = (k + 1) / n
            u = u * u * (3 - 2 * u)
            pp = {key: A._lerp(clip.pre[key], p0[key], u) for key in p0}
            sim.step(A.solve(R, pp), dt, pp["wind"])
        M, p = at(0.0)
    else:
        M, p = at(0.0)
        for _ in range(SUB * 8):
            sim.step(M, dt, p["wind"])
    base_rest, tip_rest = weapons["sword_line"]
    hist = []
    out = []
    passes = 2 if clip.loop else 1
    T = 0.0
    for ps in range(passes):
        for f in range(clip.frames):
            if not (ps == 0 and f == 0):
                for s in range(1, SUB + 1):
                    T += 1.0 / SUB
                    M, p = at(T)
                    sim.step(M, dt, p["wind"])
                    tl = T % loop_len if loop_len else T
                    if clip.trail_at(tl):
                        hist.append((T, A.bone_point(R, M, "hand.R", base_rest), A.bone_point(R, M, "hand.R", tip_rest)))
                    else:
                        hist.clear()
            else:
                M, p = at(0.0)
            if ps < passes - 1:
                continue
            sim.apply(M)
            trail = [(b, t) for (tt, b, t) in hist if tt >= T - TRAIL_LEN - 1e-6]
            out.append({"basis": A.to_basis(R, M), "M": {k: m.copy() for k, m in M.items()}, "pistol": clip.pistol_at(f),
                        "trail": trail if len(trail) >= 3 else [], "fx": clip.fx.get(f, []), "form": clip.form.get(f), "f": f})
        if clip.loop and ps == 0:
            T = 0.0
            hist.clear()
    return out


def apply_frame(rig, weapons, fr):
    for name, m in fr["basis"].items():
        rig.pose.bones[name].matrix_basis = m
    hidden = fr.get("form") is not None          # e.g. turned into a lightning spear
    for o in weapons["body"]:
        o.hide_render = hidden
    for o in weapons["pistol"]:
        o.hide_render = hidden or not fr["pistol"]
    for o in weapons["holster"]:
        o.hide_render = hidden or bool(fr["pistol"])


FX_MATS = {}


def fx_mats():
    if not FX_MATS:
        FX_MATS.update({
            "trail": A._fx_material("fx_trail", (236, 226, 255), 2.2, True, 1.0),
            "hot": A._fx_material("fx_hot", (255, 244, 214), 5.0, False, 1.0),
            "flash": A._fx_material("fx_flash", (255, 250, 228), 6.0, False, 0.92),
            "flash_fade": A._fx_material("fx_flash_fade", (255, 246, 220), 4.0, False, 0.45),
            "spark": A._fx_material("fx_spark", (206, 150, 255), 5.0, False, 1.0),
            "streak": A._fx_material("fx_streak", (214, 188, 255), 2.5, True, 0.9),
            "smoke": A._fx_material("fx_smoke", (214, 206, 236), 1.0, False, 0.4),
            "glint": A._fx_material("fx_glint", (255, 255, 255), 6.0, False, 1.0),
            "streak_dim": A._fx_material("fx_streak_dim", (214, 188, 255), 2.0, True, 0.45),
            "spear_glow": A._fx_material("fx_spear_glow", (150, 90, 255), 4.0, False, 0.7),
            "crescent": A._fx_material("fx_crescent", (230, 214, 255), 4.5, True, 1.0),
            "aura": A._fx_material("fx_aura", (190, 140, 255), 3.0, False, 0.35),
            "bolt": A._fx_material("fx_bolt", (236, 220, 255), 6.0, False, 1.0),
        })
    return FX_MATS


def build_fx(rig, R, weapons, fr):
    mats = fx_mats()
    M = fr["M"]
    objs = []

    def add(name, geo, mat, uvs=None):
        objs.append(A.fx_object(rig, name, geo[0], geo[1], mats[mat], uvs))
    if fr["trail"]:
        v, f, uv = A.trail_geo(fr["trail"])
        add("Trail", (v, f), "trail", uv)
    hl = M["hand.L"]
    muzzle = A.bone_point(R, M, "hand.L", weapons["muzzle"])
    aim = hl.col[2].xyz.normalized()
    base_rest, tip_rest = weapons["sword_line"]
    sb, st = A.bone_point(R, M, "hand.R", base_rest), A.bone_point(R, M, "hand.R", tip_rest)
    tilt = math.radians(CAM_TILT)
    cam = (rig.matrix_world.to_3x3().inverted() @ Vector((0, -math.sin(tilt), math.cos(tilt)))).normalized()   # toward the camera
    chest = M["chest"].translation + M["chest"].col[1].xyz * 0.12
    hips = M["hips"].translation
    rnd = random.Random(fr["f"] * 7919 + len(fr["fx"]))

    def bolts(pairs, width=0.011, mat="bolt"):
        for a, b in pairs:
            add("Bolt", A.bolt_geo(a, b, rnd.randrange(1 << 16), width, 6, (b - a).length * 0.12), mat)

    def crescent(span, alpha_mat, sgn, r0=0.42, r1=0.6):
        # a swoosh around her at gun height that ends where the pistol points
        end = math.atan2(aim.y, aim.x)
        c = Vector((hips.x, hips.y, muzzle.z - 0.05))
        verts, faces, uvs = [], [], []
        n = 22
        for k in range(n + 1):
            u = k / n                                   # 0 = head (at the pistol), 1 = tail
            a = end - sgn * math.radians(span) * u
            z = 0.1 * (1 - u) - 0.08 * u
            d = Vector((math.cos(a), math.sin(a), 0))
            w = r1 - (r1 - r0 - 0.03) * u
            verts += [c + d * r0 + Vector((0, 0, z)), c + d * w + Vector((0, 0, z + 0.03))]
            uvs += [(u, 0.0), (u, 1.0)]
        for k in range(n):
            faces.append((2 * k, 2 * k + 2, 2 * k + 3, 2 * k + 1))
        add("Crescent", (verts, faces), alpha_mat, uvs)

    for i, name in enumerate(fr["fx"]):
        if name == "star":
            hot = muzzle + aim * 0.05
            add("Star", A.star_geo(hot + cam * 0.05, cam, 0.34, 4, 0.11), "glint")
            add("Star2", A.star_geo(hot + cam * 0.06, cam, 0.17, 4, 0.16, twist=math.pi / 4), "glint")
            add("StarGlow", A.star_geo(hot + cam * 0.04, cam, 0.15, 12, 0.85), "flash")
            add("Muzzle", A.star_geo(muzzle + aim * 0.03, aim, 0.12, 8, 0.35, 0.4), "hot")
        elif name.startswith("crescent"):          # crescent_[fade_]l / _r: which way it curls
            sgn = -1 if name.endswith("_l") else 1
            if "fade" in name:
                crescent(110, "streak_dim", sgn, 0.5, 0.66)
            else:
                crescent(170, "crescent", sgn, 0.3, 0.62)
        elif name == "flash_in":
            add("Aura", A.star_geo(chest + cam * 0.2, cam, 0.42, 14, 0.82), "aura")
            bolts([(chest + Vector((rnd.uniform(-.2, .2), rnd.uniform(-.2, .2), rnd.uniform(-.3, .2))),
                    chest + Vector((rnd.uniform(-.45, .45), rnd.uniform(-.45, .45), rnd.uniform(-.5, .4)))) for _ in range(3)], 0.008)
        elif name in ("electro_flash", "electro_flash_small"):
            big = name == "electro_flash"
            r = 0.55 if big else 0.3
            add("Flash", A.star_geo(chest + cam * 0.25, cam, r, 4, 0.14), "glint")
            add("FlashGlow", A.star_geo(chest + cam * 0.22, cam, r * 0.6, 14, 0.8), "aura")
            out = []
            for k in range(6 if big else 3):
                a = rnd.uniform(0, 2 * math.pi)
                d = Vector((math.cos(a), math.sin(a), rnd.uniform(-0.5, 0.7))).normalized()
                out.append((chest + d * 0.08, chest + d * r * 1.1))
            bolts(out, 0.012)
        elif name == "spark_burst_body":
            bolts([(hips + Vector((rnd.uniform(-.15, .15), rnd.uniform(-.2, .2), rnd.uniform(-.6, 0))),
                    hips + Vector((rnd.uniform(-.4, .4), rnd.uniform(-.4, .4), rnd.uniform(-.2, .7)))) for _ in range(5)], 0.009)
        elif name == "blink_in":
            feet = Vector((hips.x, hips.y, 0.02))
            ring = [feet + Vector((math.cos(a) * 0.48, math.sin(a) * 0.48, 0.0)) for a in [k * math.pi / 5 + rnd.uniform(0, .3) for k in range(10)]]
            bolts([(ring[k], ring[(k + 1) % 10] + Vector((0, 0, 0.04))) for k in range(10) if k % 3 != 2], 0.012)
            bolts([(feet + Vector((rnd.uniform(-.3, .3), rnd.uniform(-.3, .3), 0)), chest + Vector((rnd.uniform(-.15, .15), rnd.uniform(-.15, .15), 0.1)))
                   for _ in range(3)], 0.01)
            add("Aura", A.star_geo(chest + cam * 0.2, cam, 0.5, 16, 0.75), "aura")
            add("Glint", A.star_geo(chest + cam * 0.25, cam, 0.22, 4, 0.15), "glint")
        elif name == "spear":
            # the lightning lance she becomes while dashing: hot core, violet sheath, crackling bolts
            y0, z0 = hips.y, hips.z + 0.18
            tail, tip = Vector((hips.x - 0.85, y0, z0 + 0.04)), Vector((hips.x + 0.95, y0, z0))
            add("SpearCore", A.lance_geo(tail, tip, 0.055, 0.62), "hot")
            add("SpearGlow", A.lance_geo(tail - Vector((0.15, 0, 0)), tip + Vector((0.1, 0, 0)), 0.15, 0.55), "spear_glow")
            add("SpearTip", A.star_geo(tip + cam * 0.05, cam, 0.2, 4, 0.14, twist=rnd.uniform(0, 0.5)), "glint")
            pts = [tail.lerp(tip, k / 6) + Vector((0, rnd.uniform(-.12, .12), rnd.uniform(-.12, .12))) for k in range(7)]
            bolts([(pts[k], pts[k + 1]) for k in range(6)], 0.012)
            bolts([(tail.lerp(tip, rnd.uniform(0.1, 0.8)), tail.lerp(tip, rnd.uniform(0, 0.6)) + Vector((-0.2, rnd.uniform(-.3, .3), rnd.uniform(-.25, .25))))
                   for _ in range(3)], 0.009)
        elif name == "muzzle":
            add("Muzzle", A.star_geo(muzzle + aim * 0.03, aim, 0.12, 8, 0.35, 0.36), "hot")
        elif name == "muzzle_small":
            add("Muzzle", A.star_geo(muzzle + aim * 0.02, aim, 0.07, 6, 0.4, 0.18, twist=0.4), "hot")
        elif name == "smoke":
            for k in range(3):
                c = muzzle + aim * (0.06 + 0.07 * k) + Vector((0, 0, 0.03 * k))
                add("Smoke", A.star_geo(c, Vector((0, 0, 1)), 0.035 + 0.015 * k, 10, 0.9), "smoke")
        elif name == "flashbang":
            add("Flash", A.star_geo(muzzle + aim * 0.3, aim, 0.42, 12, 0.3, 0.0), "flash")
            add("Flash2", A.star_geo(muzzle + aim * 0.26, Vector((0, 0, 1)), 0.3, 12, 0.3, 0.0, 0.2), "flash")
        elif name == "flashbang_fade":
            add("Flash", A.star_geo(muzzle + aim * 0.38, aim, 0.56, 12, 0.5, 0.0, 0.13), "flash_fade")
        elif name in ("spark_pistol", "spark_burst", "spark_blade"):
            seed = hash((name, i, len(objs), tuple(round(x, 2) for x in muzzle))) & 0xFFFF
            if name == "spark_pistol":
                pairs = [(muzzle - aim * 0.22 + Vector((0, 0, 0.03)), muzzle + Vector((0, 0, 0.05)))]
            elif name == "spark_burst":
                pairs = []
                for k in range(6):
                    a = k * math.pi / 3
                    d = Vector((math.cos(a) * 0.22, math.sin(a) * 0.22, 0.08 * math.sin(2 * a)))
                    pairs.append((muzzle - aim * 0.1 + d * 0.3, muzzle - aim * 0.1 + d))
            else:
                pairs = [(sb.lerp(st, 0.1 + 0.3 * k), sb.lerp(st, 0.35 + 0.3 * k) + Vector((0, 0, 0.04))) for k in range(3)]
            for j, (a, b) in enumerate(pairs):
                g1 = A.bolt_geo(a, b, seed + j, 0.01, 6, 0.04)
                add("Spark", g1, "spark")
        elif name == "streak":
            hips = M["hips"].translation
            for k, (dy, dz, ln) in enumerate(((0.18, 0.55, 0.9), (-0.16, 0.8, 1.1), (0.05, 1.15, 0.8), (-0.06, 0.35, 0.7), (0.12, 1.4, 0.6))):
                a = hips + Vector((-0.15, dy, dz - 0.94))
                verts = [a + Vector((0, 0, -0.012)), a + Vector((0, 0, 0.012)), a + Vector((-ln, 0, -0.012)), a + Vector((-ln, 0, 0.012))]
                add("Streak", (verts, [(0, 1, 3, 2)]), "streak", [(0, 0.5), (0, 1), (1, 0.5), (1, 1)])
        elif name == "glint":
            c = sb.lerp(st, 0.72)
            add("Glint", A.star_geo(c, Vector((0, -1, 0.6)), 0.09, 4, 0.18), "glint")
            add("Glint2", A.star_geo(c, Vector((0, -1, 0.6)), 0.05, 4, 0.18, twist=math.pi / 4), "glint")
    return objs


def clear_fx(objs):
    for o in objs:
        me = o.data
        bpy.data.objects.remove(o)
        bpy.data.meshes.remove(me)


def render_clips(names, out_dir, dirs=range(8), samples=16):
    import clorinde_clips as C
    sc, cam, rig, parts, weapons = build()
    try:
        sc.eevee.taa_render_samples = samples
    except AttributeError:
        pass
    R = A.RigData(rig)
    special = {id(o) for o in weapons["pistol"] + weapons["holster"]}
    weapons["body"] = [o for o in model.COLLECTION.objects if o.type == "MESH" and id(o) not in special]
    clips = [c for c in C.all_clips() if not names or c.name in names or c.name.split("#")[0] in names]
    manifest = {"anchor": anchor_px(sc, cam), "frame": FRAME_PX, "px_per_m": FRAME_PX / ORTHO, "clips": []}
    for clip in clips:
        t0 = time.time()
        frames = bake(R, clip, weapons)
        cdir = os.path.join(out_dir, clip.name.replace("@", "_at_").replace("#", "_v_"))
        os.makedirs(cdir, exist_ok=True)
        for d in dirs:
            set_direction(rig, d)
            for f, fr in enumerate(frames):
                apply_frame(rig, weapons, fr)
                objs = build_fx(rig, R, weapons, fr)
                render_to(sc, os.path.join(cdir, f"{d}_{f:02d}.png"))
                clear_fx(objs)
        manifest["clips"].append({"name": clip.name, "dir": os.path.basename(cdir), "frames": clip.frames, "fps": clip.fps,
                                  "loop": clip.loop, "hit": clip.hit, "land": clip.land, "extra": clip.extra, "stride": clip.stride})
        print(f"CLIP {clip.name}: {clip.frames} frames x {len(list(dirs))} dirs in {time.time() - t0:.1f}s", flush=True)
    path = os.path.join(out_dir, "manifest.json")
    old = {}
    if os.path.exists(path):
        with open(path) as fh:
            old = {c["name"]: c for c in json.load(fh).get("clips", [])}
    for c in manifest["clips"]:
        old[c["name"]] = c
    current = {c.name for c in C.all_clips()}
    manifest["clips"] = [c for c in old.values() if c["name"] in current]     # drop clips that no longer exist
    with open(path, "w") as fh:
        json.dump(manifest, fh, indent=1)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if argv and argv[0] == "preview":
        preview(argv[1])
    elif argv and argv[0] == "portrait":
        portrait(argv[1])
    elif argv and argv[0] == "clips":
        # clips <out_dir> <name,name|all> [dirs e.g. 1,2,3] [samples]
        names = [] if argv[2] == "all" else argv[2].split(",")
        dirs = [int(x) for x in argv[3].split(",")] if len(argv) > 3 else range(8)
        samples = int(argv[4]) if len(argv) > 4 else 16
        render_clips(names, argv[1], dirs, samples)
