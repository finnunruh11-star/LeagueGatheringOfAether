"""Clorinde's 3D model and rig, built entirely from code (run inside Blender 4.5).

The character faces +X (left = +Y, up = +Z), 1 unit = 1 m, about 1.7 m tall without the hat.
Body parts are generated meshes: rigid parts are parented to bones, cloth-like parts (torso,
coat, cape, ponytail, plume) are skinned with weights computed here. Limbs are posed with an
analytic IK in clorinde_anim.py, so the rig has no IK constraints.

This is an original design inspired by a duelist with a tricorn hat, rapier and pistol.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

V = Vector


# --------------------------------------------------------------------------- colors ---

def srgb(r, g, b):
    return tuple(((c / 255.0 + 0.055) / 1.055) ** 2.4 if c / 255.0 > 0.04045 else c / 255.0 / 12.92 for c in (r, g, b)) + (1.0,)


PALETTE = {  # name: (color, rim light, specular)
    "skin": ((252, 226, 214), 0.25, 0.0),
    "blush": ((240, 186, 186), 0.2, 0.0),
    "hair": ((56, 62, 124), 0.55, 0.35),
    "eye": ((150, 92, 230), 0.0, 0.0),
    "eye_white": ((248, 246, 255), 0.0, 0.0),
    "brow": ((30, 30, 60), 0.0, 0.0),
    "hat": ((46, 44, 82), 0.55, 0.0),
    "coat": ((60, 62, 122), 0.6, 0.12),
    "coat_dark": ((42, 42, 86), 0.5, 0.1),
    "lining": ((132, 82, 210), 0.35, 0.1),
    "vest": ((76, 56, 120), 0.4, 0.15),
    "shirt": ((242, 240, 250), 0.25, 0.0),
    "gold": ((236, 196, 106), 0.5, 0.9),
    "pants": ((50, 48, 80), 0.4, 0.05),
    "boot": ((36, 34, 54), 0.5, 0.45),
    "glove": ((52, 46, 80), 0.4, 0.2),
    "leather": ((70, 46, 52), 0.3, 0.2),
    "blade": ((214, 222, 240), 0.6, 1.0),
    "metal": ((110, 112, 136), 0.5, 0.9),
    "plume": ((176, 124, 246), 0.45, 0.1),
    "plume_tip": ((236, 222, 255), 0.4, 0.0),
}
GLOW = {"glow": (196, 148, 255), "glow_hot": (246, 232, 255)}
OUTLINE_COLOR = (22, 16, 36)
SHADOW_TINT = (118, 104, 168)       # shadows are a cool violet version of the base color


# ------------------------------------------------------------------------- materials ---

def _mix(n, kind="MIX"):
    m = n.new("ShaderNodeMix")
    m.data_type = "RGBA"
    m.blend_type = kind
    return m


def _toon_group():
    ng = bpy.data.node_groups.get("Toon")
    if ng:
        return ng
    ng = bpy.data.node_groups.new("Toon", "ShaderNodeTree")
    ng.interface.new_socket("Color", in_out="INPUT", socket_type="NodeSocketColor")
    ng.interface.new_socket("Rim", in_out="INPUT", socket_type="NodeSocketFloat")
    ng.interface.new_socket("Spec", in_out="INPUT", socket_type="NodeSocketFloat")
    ng.interface.new_socket("Shader", in_out="OUTPUT", socket_type="NodeSocketShader")
    n, lk = ng.nodes, ng.links
    gi, go = n.new("NodeGroupInput"), n.new("NodeGroupOutput")
    # diffuse light -> soft bands
    dif = n.new("ShaderNodeBsdfDiffuse")
    s2r = n.new("ShaderNodeShaderToRGB")
    bw = n.new("ShaderNodeRGBToBW")
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "EASE"
    e = ramp.color_ramp.elements
    e[0].position, e[0].color = 0.10, (0.0, 0.0, 0.0, 1)
    e[1].position, e[1].color = 0.22, (0.55, 0.55, 0.55, 1)
    e2 = e.new(0.36)
    e2.color = (1.0, 1.0, 1.0, 1)
    lk.new(dif.outputs[0], s2r.inputs[0])
    lk.new(s2r.outputs[0], bw.inputs[0])
    lk.new(bw.outputs[0], ramp.inputs[0])
    shadow = _mix(n, "MULTIPLY")
    shadow.inputs[0].default_value = 1.0
    shadow.inputs[7].default_value = srgb(*SHADOW_TINT)
    lk.new(gi.outputs["Color"], shadow.inputs[6])
    lit = _mix(n)
    lk.new(ramp.outputs[0], lit.inputs[0])
    lk.new(shadow.outputs[2], lit.inputs[6])
    lk.new(gi.outputs["Color"], lit.inputs[7])
    # rim light on the lit part of the silhouette
    lw = n.new("ShaderNodeLayerWeight")
    lw.inputs[0].default_value = 0.35
    rr = n.new("ShaderNodeMapRange")
    rr.inputs[1].default_value = 0.62
    rr.inputs[2].default_value = 0.78
    rim = n.new("ShaderNodeMath")
    rim.operation = "MULTIPLY"
    lk.new(lw.outputs["Facing"], rr.inputs[0])
    lk.new(rr.outputs[0], rim.inputs[0])
    lk.new(gi.outputs["Rim"], rim.inputs[1])
    rim_l = n.new("ShaderNodeMath")
    rim_l.operation = "MULTIPLY"
    lk.new(rim.outputs[0], rim_l.inputs[0])
    lk.new(ramp.outputs[0], rim_l.inputs[1])
    tint = _mix(n, "SCREEN")
    tint.inputs[7].default_value = srgb(214, 200, 255)
    lk.new(rim_l.outputs[0], tint.inputs[0])
    lk.new(lit.outputs[2], tint.inputs[6])
    # specular highlight band
    gl = n.new("ShaderNodeBsdfGlossy")
    gl.inputs["Roughness"].default_value = 0.28
    s2r2 = n.new("ShaderNodeShaderToRGB")
    bw2 = n.new("ShaderNodeRGBToBW")
    sr = n.new("ShaderNodeMapRange")
    sr.inputs[1].default_value = 0.45
    sr.inputs[2].default_value = 0.6
    sp = n.new("ShaderNodeMath")
    sp.operation = "MULTIPLY"
    lk.new(gl.outputs[0], s2r2.inputs[0])
    lk.new(s2r2.outputs[0], bw2.inputs[0])
    lk.new(bw2.outputs[0], sr.inputs[0])
    lk.new(sr.outputs[0], sp.inputs[0])
    lk.new(gi.outputs["Spec"], sp.inputs[1])
    add = _mix(n, "ADD")
    add.inputs[7].default_value = (0.75, 0.75, 0.8, 1)
    lk.new(sp.outputs[0], add.inputs[0])
    lk.new(tint.outputs[2], add.inputs[6])
    em = n.new("ShaderNodeEmission")
    lk.new(add.outputs[2], em.inputs[0])
    lk.new(em.outputs[0], go.inputs[0])
    return ng


def toon_material(name, rgb, rim=0.4, spec=0.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    g = nt.nodes.new("ShaderNodeGroup")
    g.node_tree = _toon_group()
    g.inputs["Color"].default_value = srgb(*rgb)
    g.inputs["Rim"].default_value = rim
    g.inputs["Spec"].default_value = spec
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(g.outputs[0], out.inputs[0])
    return m


def glow_material(name, rgb, strength=3.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = srgb(*rgb)
    em.inputs[1].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def outline_material():
    m = bpy.data.materials.get("Outline")
    if m:
        return m
    m = glow_material("Outline", OUTLINE_COLOR, 1.0)
    m.use_backface_culling = True
    return m


def mat(name):
    if name in GLOW:
        return glow_material(name, GLOW[name], 2.5 if name == "glow" else 4.0)
    rgb, rim, spec = PALETTE[name]
    return toon_material(name, rgb, rim, spec)


# -------------------------------------------------------------------------- geometry ---

def _frame(t, up):
    side = up.cross(t)
    if side.length < 1e-5:
        side = V((1, 0, 0)).cross(t) if abs(t.x) < 0.9 else V((0, 1, 0)).cross(t)
    side.normalize()
    return side, t.cross(side).normalized()


def tube(pts, rads, segs=14, up=V((0, 0, 1)), caps=True, arc=None):
    """Vertices/faces of a lofted tube along `pts`. rads[i] = (r_side, r_up) or a number
    (a single number = the same radius everywhere). arc = (a0, a1) in degrees makes an open
    sheet (0 deg = side axis, 90 = up axis)."""
    if not isinstance(rads, (list, tuple)):
        rads = [rads] * len(pts)
    verts, faces = [], []
    n = len(pts)
    ring = segs if arc is None else segs + 1
    for i in range(n):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        side, nrm = _frame(t, up)
        r = rads[i] if isinstance(rads[i], (tuple, list)) else (rads[i], rads[i])
        for k in range(ring):
            a = (2 * math.pi * k / segs) if arc is None else math.radians(arc[0] + (arc[1] - arc[0]) * k / segs)
            verts.append(pts[i] + side * math.cos(a) * r[0] + nrm * math.sin(a) * r[1])
    for i in range(n - 1):
        for k in range(segs):
            k2 = (k + 1) % ring if arc is None else k + 1
            faces.append((i * ring + k, i * ring + k2, (i + 1) * ring + k2, (i + 1) * ring + k))
    if caps and arc is None:
        for i, sgn in ((0, -1), (n - 1, 1)):
            c = len(verts)
            verts.append(pts[i].copy())
            for k in range(segs):
                a, b = i * ring + k, i * ring + (k + 1) % ring
                faces.append((a, b, c) if sgn > 0 else (b, a, c))
    return verts, faces


def ellipsoid(center, radii, segs=16, rings=10, deform=None):
    verts, faces = [], []
    for j in range(rings + 1):
        v = math.pi * j / rings
        for k in range(segs):
            u = 2 * math.pi * k / segs
            d = V((math.sin(v) * math.cos(u), math.sin(v) * math.sin(u), math.cos(v)))
            p = V((center[0] + d.x * radii[0], center[1] + d.y * radii[1], center[2] + d.z * radii[2]))
            if deform:
                p = deform(p, d)
            verts.append(p)
    for j in range(rings):
        for k in range(segs):
            a, b = j * segs + k, j * segs + (k + 1) % segs
            faces.append((a, b, b + segs, a + segs))
    return verts, faces


def bezier(pts, n=12):
    """Points on a Catmull-Rom curve through control points."""
    out = []
    P = [pts[0]] + list(pts) + [pts[-1]]
    for i in range(1, len(P) - 2):
        for s in range(n):
            t = s / n
            p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(pts[-1].copy())
    return out


COLLECTION = None
XFORM = None            # optional point transform applied to everything built (used for the head group)

# Stylized proportions: the head group (head, hair, hat) is modeled at realistic size and scaled
# up around the neck so the face reads at sprite size.
HEAD_SCALE = 1.32
HEAD_PIVOT = V((0.0, 0.0, 1.47))


def head_xf(p):
    return HEAD_PIVOT + (V(p) - HEAD_PIVOT) * HEAD_SCALE


def make_obj(name, geo, material, smooth=True, subdiv=1, outline=0.010, lining=None, thick=0.0):
    verts, faces = geo
    if XFORM:
        verts = [XFORM(v) for v in verts]
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.validate()
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    COLLECTION.objects.link(ob)
    ob.data.materials.append(mat(material))
    if lining:
        ob.data.materials.append(mat(lining))
    ob.data.materials.append(outline_material())
    if subdiv:
        m = ob.modifiers.new("Subdiv", "SUBSURF")
        m.levels = m.render_levels = subdiv
    if thick:
        m = ob.modifiers.new("Thick", "SOLIDIFY")
        m.thickness = thick
        m.offset = -1.0
        m.use_rim = True
        if lining:
            m.material_offset = 1
    if outline and material not in GLOW:
        m = ob.modifiers.new("Outline", "SOLIDIFY")
        m.thickness = outline
        m.offset = 1.0
        m.use_flip_normals = True
        m.use_rim = False
        m.material_offset = len(ob.data.materials) - 1
        m.material_offset_rim = len(ob.data.materials) - 1
    return ob


# ------------------------------------------------------------------------------ rig ---

L, R = 1, -1
# name: (head, tail, parent, roll axis: the bone's Z axis points this way at rest)
BONES = {
    "root": ((0, 0, 0), (0, 0, 0.2), None, (1, 0, 0)),
    "hips": ((0, 0, 0.94), (0, 0, 1.04), "root", (1, 0, 0)),
    "spine": ((0, 0, 1.04), (0, 0, 1.20), "hips", (1, 0, 0)),
    "chest": ((0, 0, 1.20), (0, 0, 1.40), "spine", (1, 0, 0)),
    "neck": ((0, 0, 1.41), (0, 0, 1.49), "chest", (1, 0, 0)),
    "head": ((0, 0, 1.49), (0, 0, 1.72), "neck", (1, 0, 0)),
}
for s, sg in (("L", L), ("R", R)):
    BONES.update({
        f"shoulder.{s}": ((0, 0.03 * sg, 1.385), (0, 0.165 * sg, 1.39), "chest", (0, 0, 1)),
        f"upper_arm.{s}": ((0, 0.175 * sg, 1.375), (-0.01, 0.195 * sg, 1.10), f"shoulder.{s}", (-1, 0, 0)),
        f"forearm.{s}": ((-0.01, 0.195 * sg, 1.10), (0.0, 0.205 * sg, 0.855), f"upper_arm.{s}", (-1, 0, 0)),
        f"hand.{s}": ((0.0, 0.205 * sg, 0.855), (0.0, 0.207 * sg, 0.765), f"forearm.{s}", (1, 0, 0)),
        f"thigh.{s}": ((0, 0.09 * sg, 0.92), (0.012, 0.095 * sg, 0.50), "hips", (1, 0, 0)),
        f"shin.{s}": ((0.012, 0.095 * sg, 0.50), (0, 0.1 * sg, 0.085), f"thigh.{s}", (1, 0, 0)),
        f"foot.{s}": ((0, 0.1 * sg, 0.085), (0.14, 0.1 * sg, 0.02), f"shin.{s}", (0, 0, 1)),
    })
# secondary motion chains (simulated): name -> (joint points, parent bone)
CHAINS = {
    "coat_b": ([(-0.13, 0.0, 1.00), (-0.20, 0.0, 0.76), (-0.25, 0.0, 0.52), (-0.28, 0.0, 0.30)], "hips"),
    "coat_l": ([(-0.03, 0.17, 1.00), (-0.06, 0.24, 0.76), (-0.07, 0.28, 0.52), (-0.07, 0.30, 0.31)], "hips"),
    "coat_r": ([(-0.03, -0.17, 1.00), (-0.06, -0.24, 0.76), (-0.07, -0.28, 0.52), (-0.07, -0.30, 0.31)], "hips"),
    "coat_fl": ([(0.10, 0.12, 1.00), (0.14, 0.17, 0.76), (0.17, 0.21, 0.52), (0.19, 0.23, 0.34)], "hips"),
    "coat_fr": ([(0.10, -0.12, 1.00), (0.14, -0.17, 0.76), (0.17, -0.21, 0.52), (0.19, -0.23, 0.34)], "hips"),
    "cape": ([(-0.02, 0.17, 1.44), (-0.12, 0.25, 1.24), (-0.19, 0.29, 1.04), (-0.23, 0.30, 0.86)], "chest"),
    "pony": ([(-0.11, 0.0, 1.55), (-0.16, 0.0, 1.40), (-0.19, 0.0, 1.24), (-0.20, 0.0, 1.08)], "head"),
    "plume": ([(-0.03, 0.1, 1.79), (-0.18, 0.15, 1.80), (-0.32, 0.19, 1.74)], "head"),
}


def chain_bones(name):
    return [f"{name}.{i}" for i in range(len(CHAINS[name][0]) - 1)]


def build_rig():
    arm = bpy.data.armatures.new("ClorindeRig")
    ob = bpy.data.objects.new("Rig", arm)
    COLLECTION.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones
    for name, (h, t, parent, roll_axis) in BONES.items():
        b = eb.new(name)
        b.head, b.tail = V(h), V(t)
        b.align_roll(V(roll_axis))
        if parent:
            b.parent = eb[parent]
    for name, (pts, parent) in CHAINS.items():
        if parent == "head":
            pts = [tuple(head_xf(p)) for p in pts]
        prev = eb[parent]
        for i in range(len(pts) - 1):
            b = eb.new(f"{name}.{i}")
            b.head, b.tail = V(pts[i]), V(pts[i + 1])
            d = (V(pts[i + 1]) - V(pts[i])).normalized()
            b.align_roll(V((0, 0, 1)) if abs(d.z) < 0.7 else V((1, 0, 0)))
            b.parent = prev
            b.use_connect = i > 0
            prev = b
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in ob.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return ob


def bone_world(rig, name):
    b = rig.data.bones[name]
    return b.head_local.copy(), b.tail_local.copy()


def attach(ob, rig, bone):
    """Rigid parenting that keeps the object where it was built (rest pose)."""
    mw = ob.matrix_world.copy()
    ob.parent = rig
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    bpy.context.view_layer.update()
    ob.matrix_world = mw


def _seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def skin(ob, rig, bones, sharp=4.0, bias=None):
    """Weights from the distance to bone segments (inverse power falloff), normalized."""
    segs = {b: bone_world(rig, b) for b in bones}
    groups = {b: ob.vertex_groups.new(name=b) for b in bones}
    for v in ob.data.vertices:
        p = v.co
        ws = {}
        for b, (h, t) in segs.items():
            w = 1.0 / (_seg_dist(p, h, t) + 0.01) ** sharp
            if bias:
                w *= bias(b, p)
            ws[b] = w
        tot = sum(ws.values()) or 1.0
        for b, w in ws.items():
            if w / tot > 0.01:
                groups[b].add([v.index], w / tot, "REPLACE")
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = rig
    ob.modifiers.move(len(ob.modifiers) - 1, 0)     # deform first, then subdivide / outline
    ob.parent = rig


# ---------------------------------------------------------------------------- model ---

def build_model(rig):
    parts = []

    def P(*a, **k):
        o = make_obj(*a, **k)
        parts.append(o)
        return o

    # ---- torso (vest), skinned to the spine
    rings = [  # z, x offset, half width (y), half depth (x)
        (0.86, -0.005, 0.135, 0.095), (0.94, -0.01, 0.150, 0.102), (1.03, 0.0, 0.122, 0.085),
        (1.12, 0.005, 0.128, 0.090), (1.22, 0.012, 0.142, 0.100), (1.30, 0.012, 0.152, 0.098),
        (1.37, 0.0, 0.150, 0.088), (1.41, -0.005, 0.10, 0.07), (1.43, 0.0, 0.05, 0.048)]
    pts = [V((x, 0, z)) for z, x, _, _ in rings]
    torso = P("Torso", tube(pts, [(w, d) for _, _, w, d in rings], segs=18, up=V((1, 0, 0))), "vest")
    skin(torso, rig, ["hips", "spine", "chest", "neck"])
    jab = P("Cravat", tube([V((0.085, 0, 1.40)), V((0.105, 0, 1.33)), V((0.11, 0, 1.25))], [(0.035, 0.012), (0.05, 0.016), (0.03, 0.01)],
                           segs=10, up=V((1, 0, 0))), "shirt", outline=0.006)
    attach(jab, rig, "chest")
    for i, z in enumerate((1.29, 1.22, 1.15, 1.08)):
        b = P(f"Button{i}", ellipsoid((0.103 - (1.29 - z) * 0.08, 0.0, z), (0.008, 0.012, 0.012), 8, 5), "gold", subdiv=0, outline=0.004)
        attach(b, rig, "chest" if z > 1.18 else "spine")
    belt = P("Belt", tube([V((-0.004, 0, 1.0)), V((-0.004, 0, 0.955))], [(0.14, 0.098), (0.148, 0.104)], segs=18, up=V((1, 0, 0)),
                          caps=False), "leather", outline=0.006)
    skin(belt, rig, ["hips", "spine"])
    buckle = P("Buckle", ellipsoid((0.105, 0.0, 0.978), (0.012, 0.03, 0.026), 8, 6), "gold", subdiv=0, outline=0.005)
    attach(buckle, rig, "hips")

    # ---- neck and head
    neck = P("Neck", tube([V((0.0, 0, 1.40)), V((0.005, 0, 1.52))], [0.045, 0.041], segs=12), "skin")
    attach(neck, rig, "neck")
    global XFORM
    XFORM = head_xf
    hc = V((0.005, 0.0, 1.595))

    def head_shape(p, d):
        q = p.copy()
        if d.z < 0:                                             # narrower jaw, small chin
            t = -d.z
            q.y = hc.y + (q.y - hc.y) * (1 - 0.28 * t)
            q.x += 0.012 * t * max(d.x, 0)
        if d.x > 0.3 and d.z < 0.2:                             # flatter face
            q.x -= 0.008 * d.x
        return q
    head = P("Head", ellipsoid(hc, (0.098, 0.088, 0.112), 20, 14, head_shape), "skin")
    attach(head, rig, "head")
    for sg in (L, R):                                            # big eyes, highlights, lashes, brows, blush
        y = 0.036 * sg
        face = [
            P(f"EyeWhite{sg}", ellipsoid((0.087, y, 1.588), (0.009, 0.021, 0.026), 10, 6), "eye_white", subdiv=0, outline=0.0),
            P(f"Iris{sg}", ellipsoid((0.093, y + 0.002 * sg, 1.585), (0.006, 0.016, 0.022), 10, 6), "eye", subdiv=0, outline=0.0),
            P(f"EyeHi{sg}", ellipsoid((0.0985, y - 0.005 * sg, 1.596), (0.002, 0.006, 0.006), 6, 4), "eye_white", subdiv=0, outline=0.0),
            P(f"Lash{sg}", tube([V((0.09, y - 0.023 * sg, 1.608)), V((0.096, y, 1.615)), V((0.089, y + 0.025 * sg, 1.606))],
                                [0.004, 0.0048, 0.003], segs=6), "brow", subdiv=0, outline=0.0),
            P(f"Brow{sg}", tube([V((0.094, y - 0.016 * sg, 1.634)), V((0.095, y + 0.016 * sg, 1.638))], [0.0025, 0.002], segs=6),
              "brow", subdiv=0, outline=0.0),
            P(f"Blush{sg}", ellipsoid((0.082, y * 1.25, 1.562), (0.004, 0.014, 0.006), 8, 4), "blush", subdiv=0, outline=0.0),
        ]
        for o in face:
            attach(o, rig, "head")
    mouth = P("Mouth", tube([V((0.093, -0.01, 1.538)), V((0.095, 0.0, 1.536)), V((0.093, 0.01, 1.538))], [0.002, 0.0022, 0.002], segs=6),
              "brow", subdiv=0, outline=0.0)
    attach(mouth, rig, "head")

    # ---- hair: cap, bangs, side locks, back curtain (rigid) and ponytail (simulated)
    def cap_shape(p, d):
        q = p.copy()
        if d.z < -0.1 and d.x < 0:
            q.z -= 0.03 * (-d.z)
        return q
    capv, capf = ellipsoid(hc + V((-0.008, 0, 0.01)), (0.108, 0.098, 0.118), 22, 14, cap_shape)
    keep = [f for f in capf if not (sum(capv[i].x for i in f) / 4 > hc.x + 0.03 and sum(capv[i].z for i in f) / 4 < hc.z + 0.055)]
    cap = P("HairCap", (capv, keep), "hair", thick=0.012)
    attach(cap, rig, "head")
    for i, y in enumerate((-0.078, -0.05, -0.02, 0.014, 0.044, 0.074)):      # parted bangs ending above the brows
        ln = (0.0, 0.012, 0.004, 0.0, 0.01, 0.002)[i]
        sw = 1.3 if abs(y) > 0.03 else 1.18
        pts = bezier([V((0.03, y * 0.9, 1.715)), V((0.094, y, 1.685)), V((0.11, y * 1.1, 1.66 - ln * 0.5)), V((0.106, y * sw, 1.645 - ln))], 4)
        rad = [(0.018 - 0.013 * k / (len(pts) - 1), 0.008 - 0.004 * k / (len(pts) - 1)) for k in range(len(pts))]
        o = P(f"Bang{i}", tube(pts, rad, segs=8, up=V((1, 0, 0))), "hair", outline=0.006)
        attach(o, rig, "head")
    for sg in (L, R):
        pts = bezier([V((0.04, 0.085 * sg, 1.68)), V((0.07, 0.102 * sg, 1.58)), V((0.065, 0.108 * sg, 1.48)), V((0.05, 0.10 * sg, 1.40))], 5)
        rad = [(0.024 - 0.016 * k / (len(pts) - 1), 0.01) for k in range(len(pts))]
        o = P(f"SideLock{sg}", tube(pts, rad, segs=8, up=V((0, sg, 0))), "hair", outline=0.006)
        attach(o, rig, "head")
    pts = bezier([V((-0.07, 0, 1.70)), V((-0.115, 0, 1.6)), V((-0.11, 0, 1.48)), V((-0.095, 0, 1.42))], 5)
    rad = [(0.095, 0.03)] * 2 + [(0.09, 0.028)] * (len(pts) - 4) + [(0.07, 0.022), (0.05, 0.015)]
    back = P("HairBack", tube(pts, rad, segs=12, up=V((-1, 0, 0))), "hair")
    attach(back, rig, "head")
    pp = [V(p) for p in CHAINS["pony"][0]]
    pts = bezier([pp[0] + V((0.02, 0, 0.02))] + pp, 5)
    n = len(pts) - 1
    pony = P("Ponytail", tube(pts, [(0.045 - 0.032 * (k / n) ** 0.8, 0.032 - 0.022 * k / n) for k in range(n + 1)], segs=12, up=V((0, 1, 0))), "hair")
    skin(pony, rig, ["head"] + chain_bones("pony"), sharp=5)
    tie = P("HairTie", ellipsoid(pp[0] + V((0.0, 0, -0.01)), (0.03, 0.04, 0.025), 10, 6), "lining", outline=0.006)
    attach(tie, rig, "head")

    # ---- hat (rigid on the head) with a simulated plume
    hb = hc + V((-0.005, 0.0, 0.075))
    tilt = Matrix.Rotation(math.radians(-6), 4, "X") @ Matrix.Rotation(math.radians(-22), 4, "Y")   # cocked back to show the face

    def hat_xf(p):
        return hb + (tilt @ (p - hb))
    bv, bf = [], []
    segs = 40
    for k in range(segs):
        th = 2 * math.pi * k / segs
        for j, r in enumerate((0.085, 0.14, 0.19)):
            up = 0.0 if j == 0 else 0.06 * (r / 0.19) ** 2 * max(0.0, math.cos(1.5 * (th - math.radians(140)))) ** 2 \
                + 0.05 * (r / 0.19) ** 2 * max(0.0, math.cos(1.5 * (th + math.radians(110)))) ** 2
            rx = r * (1.0 - 0.2 * max(math.cos(th), 0.0))     # short front brim so the face stays visible from above
            bv.append(hat_xf(hb + V((math.cos(th) * rx, math.sin(th) * r, up))))
    for k in range(segs):
        for j in range(2):
            a, b = k * 3 + j, ((k + 1) % segs) * 3 + j
            bf.append((a, b, b + 1, a + 1))
    brim = P("HatBrim", (bv, bf), "hat", thick=0.012)
    attach(brim, rig, "head")
    rim_pts = [bv[k * 3 + 2] for k in range(segs)] + [bv[2]]
    trim = P("HatTrim", tube(rim_pts, 0.0075, segs=6, caps=False), "gold", subdiv=0, outline=0.004)
    attach(trim, rig, "head")
    crown_pts = [hat_xf(hb + V((0, 0, z))) for z in (0.0, 0.05, 0.10, 0.125, 0.135)]
    crown = P("HatCrown", tube(crown_pts, [(0.098, 0.106), (0.094, 0.102), (0.086, 0.094), (0.06, 0.07), (0.005, 0.005)], segs=20,
                               up=V((1, 0, 0))), "hat")
    attach(crown, rig, "head")
    band = P("HatBand", tube([hat_xf(hb + V((0, 0, 0.012))), hat_xf(hb + V((0, 0, 0.042)))], [(0.1, 0.108), (0.097, 0.105)], segs=20,
                             up=V((1, 0, 0)), caps=False), "lining", outline=0.004)
    attach(band, rig, "head")
    brooch = P("Brooch", ellipsoid(hat_xf(hb + V((0.06, 0.08, 0.03))), (0.016, 0.016, 0.022), 10, 6), "gold", subdiv=0, outline=0.004)
    gem = P("BroochGem", ellipsoid(hat_xf(hb + V((0.072, 0.088, 0.03))), (0.008, 0.009, 0.013), 8, 5), "glow", subdiv=0, outline=0.0)
    for o in (brooch, gem):
        attach(o, rig, "head")
    plp = [V(p) for p in CHAINS["plume"][0]]
    pts = bezier([plp[0] + V((0.05, -0.02, -0.02))] + plp, 6)
    n = len(pts) - 1
    fup = V((0, 0.3, 1.0)).normalized()          # feather lies almost flat, tilted a little outward
    plume = P("Plume", tube(pts, [(0.01 + 0.036 * math.sin(math.pi * min(1, k / n * 1.15)) * (1 - k / n * 0.4), 0.007) for k in range(n + 1)],
                            segs=10, up=fup), "plume", outline=0.007)
    skin(plume, rig, ["head"] + chain_bones("plume"), sharp=5)
    tip = P("PlumeTip", tube(pts[-6:], [(0.024 - 0.004 * k, 0.0075) for k in range(6)], segs=8, up=fup), "plume_tip", outline=0.0)
    skin(tip, rig, chain_bones("plume"), sharp=5)
    XFORM = None
    for o in (brim, trim, crown, band, brooch, gem, plume, tip):
        o.visible_shadow = False            # the hat must not throw the face into shadow

    # ---- coat: upper body, collar, long open skirt (lining inside) and gold edges
    up_rings = [(1.43, 0.12, 0.085, 0.0), (1.40, 0.175, 0.105, 0.0), (1.33, 0.172, 0.112, 0.0), (1.22, 0.158, 0.11, 0.01),
                (1.10, 0.138, 0.098, 0.0), (1.01, 0.142, 0.102, 0.0)]
    gap = 26
    coat_u = P("CoatUpper", tube([V((x, 0, z)) for z, w, d, x in up_rings], [(w, d) for z, w, d, x in up_rings], segs=26, up=V((1, 0, 0)),
                                 arc=(90 + gap, 450 - gap)), "coat", lining="lining", thick=0.01)
    skin(coat_u, rig, ["hips", "spine", "chest", "neck", "shoulder.L", "shoulder.R"], sharp=4)
    collar = P("Collar", tube([V((-0.005, 0, 1.42)), V((-0.012, 0, 1.50))], [(0.085, 0.072), (0.092, 0.08)], segs=20, up=V((1, 0, 0)),
                              arc=(90 + 38, 450 - 38)), "coat", lining="lining", thick=0.008)
    skin(collar, rig, ["chest", "neck"], sharp=4)
    sk_rings = [(1.0, 0.148, 0.108), (0.86, 0.17, 0.13), (0.70, 0.205, 0.165), (0.52, 0.24, 0.20), (0.34, 0.265, 0.225)]
    sgap = [30, 36, 42, 48, 54]
    sk_segs = 28
    verts, faces = [], []
    ring_n = sk_segs + 1
    for i, (z, w, d) in enumerate(sk_rings):
        for k in range(ring_n):
            a = math.radians(90 + sgap[i] + (360 - 2 * sgap[i]) * k / sk_segs)     # 90 = front (+X), 270 = back
            x, y = math.sin(a) * d, -math.cos(a) * w
            drop = 0.12 * max(0.0, -math.sin(a)) ** 2 * (i / (len(sk_rings) - 1)) ** 1.5   # longer at the back
            verts.append(V((x - 0.01, y, z - drop)))
    for i in range(len(sk_rings) - 1):
        for k in range(sk_segs):
            faces.append((i * ring_n + k, i * ring_n + k + 1, (i + 1) * ring_n + k + 1, (i + 1) * ring_n + k))
    skirt = P("CoatSkirt", (verts, faces), "coat", lining="lining", thick=0.01)
    chains = ["coat_b", "coat_l", "coat_r", "coat_fl", "coat_fr"]
    skirt_bones = ["hips"] + [b for c in chains for b in chain_bones(c)]

    def skirt_bias(b, p):
        return (3.0 if p.z > 0.95 else 0.4) if b == "hips" else 1.0
    skin(skirt, rig, skirt_bones, sharp=3, bias=skirt_bias)
    edge_l = [verts[i * ring_n + 0] for i in range(len(sk_rings))]
    edge_r = [verts[i * ring_n + sk_segs] for i in range(len(sk_rings))]
    hem = [verts[(len(sk_rings) - 1) * ring_n + k] for k in range(ring_n)]
    for nm, pts in (("TrimL", bezier(edge_l, 3)), ("TrimR", bezier(edge_r, 3)), ("TrimHem", hem)):
        o = P(nm, tube(pts, 0.008, segs=6, caps=False), "gold", subdiv=0, outline=0.004)
        skin(o, rig, skirt_bones, sharp=3, bias=skirt_bias)
    for sg, nm in ((L, "L"), (R, "R")):
        pts = []
        for z, w, d, x in up_rings:
            a = math.radians(90 + gap) if sg == R else math.radians(450 - gap)
            pts.append(V((x + math.sin(a) * d, -math.cos(a) * w, z)))
        o = P(f"TrimUp{nm}", tube(pts, 0.008, segs=6, caps=False), "gold", subdiv=0, outline=0.004)
        skin(o, rig, ["hips", "spine", "chest", "neck"], sharp=4)

    # ---- half cape on the left shoulder
    cp = [V(p) for p in CHAINS["cape"][0]]
    cverts, cfaces = [], []
    cs = 14
    for i, c in enumerate(cp):
        wdt = 0.13 + 0.09 * i / (len(cp) - 1)
        for k in range(cs + 1):
            a = math.radians(-70 + 230 * k / cs)                         # wraps from front-left over to the back
            cverts.append(c + V((math.cos(a) * wdt * 0.9 + 0.02, math.sin(a) * wdt * 0.55 - 0.02, 0.0)))
    for i in range(len(cp) - 1):
        for k in range(cs):
            cfaces.append((i * (cs + 1) + k, i * (cs + 1) + k + 1, (i + 1) * (cs + 1) + k + 1, (i + 1) * (cs + 1) + k))
    cape = P("Cape", (cverts, cfaces), "coat_dark", lining="lining", thick=0.01)

    def cape_bias(b, p):
        return (2.5 if p.z > 1.38 else 0.3) if b in ("chest", "shoulder.L") else 1.0
    skin(cape, rig, ["chest", "shoulder.L"] + chain_bones("cape"), sharp=3, bias=cape_bias)
    chem = [cverts[(len(cp) - 1) * (cs + 1) + k] for k in range(cs + 1)]
    o = P("CapeTrim", tube(chem, 0.008, segs=6, caps=False), "gold", subdiv=0, outline=0.004)
    skin(o, rig, chain_bones("cape"), sharp=3)
    for sg in (L, R):
        s = "L" if sg == L else "R"
        pad = P(f"Pad{s}", ellipsoid((-0.005, 0.17 * sg, 1.39), (0.07, 0.065, 0.045), 14, 8,
                                     lambda p, d: p if d.z > -0.2 else V((p.x, p.y, 1.39 - 0.009))), "coat")
        attach(pad, rig, f"shoulder.{s}")
        ring_pts = [V((math.cos(t) * 0.07 - 0.005, 0.17 * sg + math.sin(t) * 0.065, 1.382)) for t in [i * math.pi / 8 for i in range(17)]]
        rim_ = P(f"PadRim{s}", tube(ring_pts, 0.006, segs=6, caps=False), "gold", subdiv=0, outline=0.003)
        attach(rim_, rig, f"shoulder.{s}")

    # ---- arms: sleeves, flared cuffs, gloves
    for sg in (L, R):
        s = "L" if sg == L else "R"
        sh, el = bone_world(rig, f"upper_arm.{s}")
        _, wr = bone_world(rig, f"forearm.{s}")
        ua = P(f"Sleeve{s}", tube([sh + V((0, 0, 0.02)), sh.lerp(el, 0.5), el], [0.056, 0.05, 0.045], segs=14), "coat")
        attach(ua, rig, f"upper_arm.{s}")
        elbow = P(f"Elbow{s}", ellipsoid(el, (0.046, 0.046, 0.046), 12, 8), "coat")
        fa = P(f"Forearm{s}", tube([el, el.lerp(wr, 0.55), wr + V((0, 0, 0.03))], [0.045, 0.04, 0.036], segs=14), "coat")
        cuff = P(f"Cuff{s}", tube([el.lerp(wr, 0.62), wr + V((0, 0, 0.015))], [0.05, 0.062], segs=14, caps=False), "lining",
                 thick=0.008, outline=0.006)
        ring_pts = [wr + V((math.cos(t) * 0.062, math.sin(t) * 0.062, 0.015)) for t in [i * math.pi / 8 for i in range(17)]]
        crim = P(f"CuffRim{s}", tube(ring_pts, 0.0055, segs=6, caps=False), "gold", subdiv=0, outline=0.003)
        for o in (elbow, fa, cuff, crim):
            attach(o, rig, f"forearm.{s}")
        h0, h1 = bone_world(rig, f"hand.{s}")
        fist = P(f"Hand{s}", ellipsoid(h0.lerp(h1, 0.45), (0.04, 0.03, 0.05), 12, 8), "glove", outline=0.007)
        thumb = P(f"Thumb{s}", tube([h0 + V((0.025, -0.012 * sg, -0.015)), h0 + V((0.045, -0.005 * sg, -0.05))], [0.014, 0.011], segs=8),
                  "glove", outline=0.005)
        for o in (fist, thumb):
            attach(o, rig, f"hand.{s}")

    # ---- legs: trousers, tall boots with gold cuffs
    for sg in (L, R):
        s = "L" if sg == L else "R"
        hp, kn = bone_world(rig, f"thigh.{s}")
        _, an = bone_world(rig, f"shin.{s}")
        th = P(f"Thigh{s}", tube([hp + V((0, 0, 0.03)), hp.lerp(kn, 0.5), kn], [0.08, 0.066, 0.053], segs=14), "pants")
        attach(th, rig, f"thigh.{s}")
        knee = P(f"Knee{s}", ellipsoid(kn, (0.054, 0.052, 0.054), 12, 8), "boot")
        boot = P(f"Boot{s}", tube([kn + V((0.004, 0, 0.04)), kn.lerp(an, 0.4), an], [(0.06, 0.058), 0.047, 0.042], segs=14), "boot")
        bcuff = P(f"BootCuff{s}", tube([kn + V((0.004, 0, 0.0)), kn + V((0.004, 0, 0.05))], [0.058, 0.062], segs=14, caps=False), "boot",
                  thick=0.008, outline=0.006)
        ring_pts = [kn + V((0.004 + math.cos(t) * 0.062, math.sin(t) * 0.062, 0.05)) for t in [i * math.pi / 8 for i in range(17)]]
        brim2 = P(f"BootRim{s}", tube(ring_pts, 0.0065, segs=6, caps=False), "gold", subdiv=0, outline=0.003)
        for o in (knee, boot, bcuff, brim2):
            attach(o, rig, f"shin.{s}")
        foot = P(f"Foot{s}", tube([an + V((-0.035, 0, -0.03)), an + V((0.03, 0, -0.045)), an + V((0.15, 0, -0.065))],
                                  [(0.042, 0.05), (0.044, 0.035), (0.03, 0.018)], segs=12), "boot")
        heel = P(f"Heel{s}", ellipsoid(an + V((-0.03, 0, -0.07)), (0.026, 0.03, 0.018), 8, 5), "boot", subdiv=0, outline=0.005)
        for o in (foot, heel):
            attach(o, rig, f"foot.{s}")

    return parts, build_weapons(rig)


PISTOL_SCALE = 1.3


def build_weapons(rig):
    """Rapier in the right hand, flintlock pistol in the left hand and one holstered on the left hip.
    In the rest pose both point along +X out of the fist (the hand bones' Z axis)."""
    out = {}
    h0, h1 = bone_world(rig, "hand.R")
    g = h0.lerp(h1, 0.45)
    objs = []

    def W(*a, **k):
        o = make_obj(*a, **k)
        objs.append(o)
        return o
    W("Grip", tube([g + V((-0.06, 0, 0)), g + V((0.05, 0, 0))], [0.013, 0.012], segs=8), "leather", outline=0.005)
    W("Pommel", ellipsoid(g + V((-0.075, 0, 0)), (0.02, 0.018, 0.018), 10, 6), "gold", outline=0.005)
    W("Quillon", tube([g + V((0.06, -0.075, 0)), g + V((0.06, 0, 0)), g + V((0.06, 0.075, 0))], [0.007, 0.01, 0.007], segs=8), "gold",
      outline=0.004)
    knuckle = bezier([g + V((0.06, 0, 0.0)), g + V((0.04, 0, -0.06)), g + V((-0.02, 0, -0.065)), g + V((-0.065, 0, -0.01))], 5)
    W("Knuckle", tube(knuckle, 0.0055, segs=6), "gold", subdiv=0, outline=0.004)
    W("Cup", ellipsoid(g + V((0.065, 0, 0)), (0.012, 0.045, 0.045), 12, 6), "gold", outline=0.004)
    W("SwordGem", ellipsoid(g + V((0.075, 0, 0)), (0.008, 0.012, 0.012), 8, 5), "glow", subdiv=0, outline=0.0)
    W("Blade", tube([g + V((0.07, 0, 0)), g + V((0.45, 0, 0)), g + V((0.86, 0, 0))], [(0.005, 0.018), (0.0045, 0.013), (0.0015, 0.003)],
                    segs=4, up=V((0, 1, 0))), "blade", subdiv=0, outline=0.004)
    for o in objs:
        attach(o, rig, "hand.R")
    out["sword"] = objs
    out["sword_line"] = (g + V((0.12, 0, 0)), g + V((0.86, 0, 0)))      # (base, tip) in rest pose, for trails

    def pistol(prefix, at, bone, rot=None):
        objs = []

        def P2(*a, **k):
            o = make_obj(*a, **k)
            objs.append(o)
            return o
        P2(prefix + "Barrel", tube([at + V((0.0, 0, 0.03)), at + V((0.3, 0, 0.03))], [0.017, 0.015], segs=8), "metal", subdiv=0, outline=0.005)
        P2(prefix + "Rune", tube([at + V((0.04, 0, 0.047)), at + V((0.27, 0, 0.044))], [0.0035, 0.003], segs=6), "glow", subdiv=0, outline=0.0)
        for i, x in enumerate((0.05, 0.17, 0.285)):
            P2(prefix + f"Band{i}", tube([at + V((x, 0, 0.03)), at + V((x + 0.014, 0, 0.03))], [0.02, 0.02], segs=8), "gold", subdiv=0,
               outline=0.003)
        stock = bezier([at + V((0.06, 0, 0.03)), at + V((0.0, 0, 0.0)), at + V((-0.04, 0, -0.06)), at + V((-0.065, 0, -0.1))], 4)
        n = len(stock) - 1
        P2(prefix + "Stock", tube(stock, [(0.016 + 0.006 * k / n, 0.022 + 0.008 * k / n) for k in range(n + 1)], segs=8, up=V((0, 1, 0))),
           "leather", outline=0.005)
        P2(prefix + "Cap", ellipsoid(at + V((-0.068, 0, -0.105)), (0.022, 0.02, 0.016), 8, 5), "gold", subdiv=0, outline=0.004)
        P2(prefix + "Hammer", tube([at + V((0.02, 0, 0.045)), at + V((0.0, 0, 0.07))], [0.007, 0.005], segs=6), "metal", subdiv=0, outline=0.003)
        big = Matrix.Translation(at) @ Matrix.Scale(PISTOL_SCALE, 4) @ Matrix.Translation(-at)      # oversized so it reads at sprite size
        for o in objs:
            o.matrix_world = big @ o.matrix_world
        if rot is not None:
            for o in objs:
                o.matrix_world = Matrix.Translation(at) @ rot @ Matrix.Translation(-at) @ o.matrix_world
        for o in objs:
            attach(o, rig, bone)
        return objs
    h0, h1 = bone_world(rig, "hand.L")
    gl = h0.lerp(h1, 0.45)
    out["pistol"] = pistol("Pistol", gl, "hand.L")
    out["muzzle"] = gl + V((0.31, 0, 0.03)) * PISTOL_SCALE
    out["holster"] = pistol("Holstered", V((-0.06, 0.165, 0.9)), "hips",
                            Matrix.Rotation(math.radians(115), 4, "Y") @ Matrix.Rotation(math.radians(-15), 4, "Z"))
    return out


def build_all():
    global COLLECTION
    COLLECTION = bpy.data.collections.new("Clorinde")
    bpy.context.scene.collection.children.link(COLLECTION)
    rig = build_rig()
    parts, weapons = build_model(rig)
    return rig, parts, weapons
