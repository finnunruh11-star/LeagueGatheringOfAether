"""Pose solver, secondary motion and effects for Clorinde's sprite animations (runs inside Blender).

A pose is a dict of high-level parameters (see NEUTRAL). Clips are lists of key poses at frame
times; every frame is interpolated (Hermite), solved into armature-space bone matrices (FK spine,
analytic two-bone IK for arms and legs, hands oriented by where the weapon points), then the coat,
cape, ponytail and plume chains are simulated (Verlet springs with leg/torso collisions).
Angles are degrees. Rig space: +X forward, +Y left, +Z up, meters.
"""
import math

import bpy
from mathutils import Matrix, Vector

import clorinde_model as model

V = Vector
D2R = math.pi / 180.0

NEUTRAL = {
    "body": (0.0, 0.0, 0.0),            # pelvis offset
    "hips": (0.0, 0.0, 0.0),            # (twist: + turns left, lean: + forward, side: + leans left), about each bone's head
    "spine": (0.0, 0.0, 0.0),
    "chest": (0.0, 0.0, 0.0),
    "neck": (0.0, 0.0, 0.0),
    "head": (0.0, 0.0, 0.0),
    "shL": (0.0, 0.0), "shR": (0.0, 0.0),           # shoulder (lift, forward)
    "footL": (0.0, 0.1, 0.085), "footR": (0.0, -0.1, 0.085),   # ankle positions (rig space)
    "toeL": 0.0, "toeR": 0.0,                       # foot pitch, + = toes up
    "fyawL": 0.0, "fyawR": 0.0,                     # foot yaw, + = toes turn left
    "kneeL": (1.0, 0.15, 0.0), "kneeR": (1.0, -0.15, 0.0),
    "handR": (0.02, -0.24, 0.84), "aimR": (1.0, 0.0, 0.0), "rollR": 0.0, "elbowR": (-0.7, -0.5, -0.3),
    "handL": (0.02, 0.24, 0.84), "aimL": (1.0, 0.0, 0.0), "rollL": 0.0, "elbowL": (-0.7, 0.5, -0.3),
    "rot": (0.0, 0.0, 0.0),             # whole-character rotation (x, y, z) about `pivot`, then `move`
    "pivot": (0.0, 0.0, 0.0),
    "move": (0.0, 0.0, 0.0),
    "wind": (0.0, 0.0, 0.0),            # air velocity for the cloth (m/s), e.g. backwards while running
}


def pose(base=None, **kw):
    p = dict(NEUTRAL if base is None else base)
    for k, v in kw.items():
        if k not in NEUTRAL:
            raise KeyError(k)
        p[k] = v
    return p


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


# ----------------------------------------------------------------------------- rig data ---

class RigData:
    def __init__(self, rig):
        self.rig = rig
        bones = rig.data.bones
        self.order = [b.name for b in bones]
        self.rest = {b.name: b.matrix_local.copy() for b in bones}
        self.irest = {k: m.inverted() for k, m in self.rest.items()}
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        self.length = {b.name: b.length for b in bones}
        self.chains = {}
        for name, (pts, parent) in model.CHAINS.items():
            if parent == "head":
                pts = [tuple(model.head_xf(p)) for p in pts]
            self.chains[name] = ([V(p) for p in pts], parent, model.chain_bones(name))


def rot3(tw, ln, sd):
    return (Matrix.Rotation(tw * D2R, 4, "Z") @ Matrix.Rotation(ln * D2R, 4, "Y") @ Matrix.Rotation(-sd * D2R, 4, "X"))


def basis(head, y, zh):
    y = y.normalized()
    z = zh - y * zh.dot(y)
    if z.length < 1e-6:
        z = V((0, 0, 1)) - y * y.z if abs(y.z) < 0.9 else V((1, 0, 0)) - y * y.x
    z.normalize()
    x = y.cross(z)
    return Matrix(((x.x, y.x, z.x, head.x), (x.y, y.y, z.y, head.y), (x.z, y.z, z.z, head.z), (0, 0, 0, 1)))


def two_bone(a, target, l1, l2, pole):
    d = target - a
    dist = min(max(d.length, abs(l1 - l2) + 1e-4), (l1 + l2) * 0.9995)
    dn = d.normalized()
    x = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - x * x, 0.0))
    n = pole - dn * pole.dot(dn)
    if n.length < 1e-6:
        n = V((0, 0, -1)) - dn * dn.z
    n.normalize()
    elbow = a + dn * x + n * h
    end = a + dn * dist
    return elbow, end, n


def solve(R, p):
    """Pose dict -> {bone: armature-space matrix}. Chains are rigid here (see Sim)."""
    M = {}
    rest, irest = R.rest, R.irest

    def fk(bone, R3, pre=None):
        par = R.parent[bone]
        head = rest[bone].translation
        local = Matrix.Translation(head) @ R3 @ Matrix.Translation(-head) @ rest[bone]
        m = (M[par] @ irest[par] @ local) if par else local
        M[bone] = (pre @ m) if pre is not None else m

    M["root"] = rest["root"].copy()
    fk("hips", rot3(*p["hips"]), Matrix.Translation(V(p["body"])))
    for b in ("spine", "chest", "neck", "head"):
        fk(b, rot3(*p[b]))
    for s, sg in (("L", 1), ("R", -1)):
        lift, fwd = p["sh" + s]
        fk(f"shoulder.{s}", Matrix.Rotation(-sg * fwd * D2R, 4, "Z") @ Matrix.Rotation(sg * lift * D2R, 4, "X"))
    dhips = M["hips"] @ irest["hips"]
    # hands: rig-space targets carried along by the chest's translation (not its rotation)
    sp = Matrix.Translation(M["chest"].translation - rest["chest"].translation)
    sp3 = Matrix.Identity(3)
    # arms
    for s, sg in (("L", 1), ("R", -1)):
        ua, fa, hb = f"upper_arm.{s}", f"forearm.{s}", f"hand.{s}"
        S = (M[f"shoulder.{s}"] @ irest[f"shoulder.{s}"] @ rest[ua]).translation
        G = sp @ V(p["hand" + s])
        A = (sp3 @ V(p["aim" + s])).normalized()
        F = (G - S) - A * (G - S).dot(A)
        if F.length < 0.05:
            F = V((0, 0, -1)) - A * A.z
        F.normalize()
        if p["roll" + s]:
            F = Matrix.Rotation(p["roll" + s] * D2R, 3, A) @ F
        grip = R.length[hb] * 0.45
        W = G - F * grip
        pole = sp3 @ V(p["elbow" + s])
        E, Wr, n = two_bone(S, W, R.length[ua], R.length[fa], pole)
        M[ua] = basis(S, E - S, n)
        M[fa] = basis(E, Wr - E, n)
        M[hb] = basis(Wr, F, A)
    # legs
    p0 = math.atan2(-0.065, 0.14)
    for s, sg in (("L", 1), ("R", -1)):
        th, sh, ft = f"thigh.{s}", f"shin.{s}", f"foot.{s}"
        H = (M["hips"] @ irest["hips"] @ rest[th]).translation
        A = V(p["foot" + s])
        yaw = p["fyaw" + s] * D2R
        knee = (dhips.to_3x3() @ V(p["knee" + s])) + V((math.cos(yaw), math.sin(yaw), 0)) * 0.5
        K, An, n = two_bone(H, A, R.length[th], R.length[sh], knee)
        M[th] = basis(H, K - H, n)
        M[sh] = basis(K, An - K, n)
        pitch = p0 + p["toe" + s] * D2R
        M[ft] = basis(An, V((math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), math.sin(pitch))), V((0, 0, 1)))
    # chains follow their parent rigidly (the simulation replaces them)
    for name, (pts, parent, bones) in R.chains.items():
        d = M[parent] @ irest[parent]
        for b in bones:
            M[b] = d @ rest[b]
    g = Matrix.Translation(V(p["move"])) @ Matrix.Translation(V(p["pivot"])) @ rot3(p["rot"][2], p["rot"][1], -p["rot"][0]) \
        @ Matrix.Translation(-V(p["pivot"]))
    if g != Matrix.Identity(4):
        for k in M:
            M[k] = g @ M[k]
    return M


def to_basis(R, M):
    out = {}
    for b in R.order:
        par = R.parent[b]
        if par:
            out[b] = R.irest[b] @ R.rest[par] @ M[par].inverted() @ M[b]
        else:
            out[b] = R.irest[b] @ M[b]
    return out


def bone_point(R, M, bone, rest_point):
    return M[bone] @ R.irest[bone] @ V(rest_point)


# ------------------------------------------------------------------------ interpolation ---

def _lerp(a, b, t):
    if isinstance(a, tuple):
        return tuple(x + (y - x) * t for x, y in zip(a, b))
    return a + (b - a) * t


def _vec(op, *xs):
    if isinstance(xs[0], tuple):
        return tuple(op(*c) for c in zip(*xs))
    return op(*xs)


def sample(keys, t, loop_len=None):
    """keys: [(time, pose dict, tension)] sorted. Hermite interpolation of every parameter."""
    n = len(keys)
    if loop_len:
        t = t % loop_len
        ext = [(keys[-1][0] - loop_len, keys[-1][1], keys[-1][2])] + list(keys) + [(keys[0][0] + loop_len, keys[0][1], keys[0][2]),
                                                                                  (keys[1 % n][0] + loop_len, keys[1 % n][1], keys[1 % n][2])]
    else:
        if t <= keys[0][0]:
            return dict(keys[0][1])
        if t >= keys[-1][0]:
            return dict(keys[-1][1])
        ext = [keys[0]] + list(keys) + [keys[-1]]
    for i in range(1, len(ext) - 2):
        if ext[i][0] <= t < ext[i + 1][0] or (i == len(ext) - 3):
            break
    (t0, a, e0), (t1, b, e1) = ext[i], ext[i + 1]
    (tp, pa, _), (tn, nb, _) = ext[i - 1], ext[i + 2]
    h = max(t1 - t0, 1e-6)
    u = min(max((t - t0) / h, 0.0), 1.0)
    h00, h10, h01, h11 = 2 * u ** 3 - 3 * u ** 2 + 1, u ** 3 - 2 * u ** 2 + u, -2 * u ** 3 + 3 * u ** 2, u ** 3 - u ** 2
    out = {}
    for k in a:
        va, vb, vp, vn = a[k], b[k], pa[k], nb[k]
        m0 = _vec(lambda x, y: (y - x) / max(t1 - tp, 1e-6) * h * e0, vp, vb) if t1 - tp > 1e-6 else _vec(lambda x: 0.0, va)
        m1 = _vec(lambda x, y: (y - x) / max(tn - t0, 1e-6) * h * e1, va, vn) if tn - t0 > 1e-6 else _vec(lambda x: 0.0, va)
        out[k] = _vec(lambda A, B, C, Dd: h00 * A + h10 * C + h01 * B + h11 * Dd, va, vb, m0, m1)
    return out


# --------------------------------------------------------------------------- simulation ---

CHAIN_SETTINGS = {  # stiffness (1/s), damping (1/s), drag (1/s), collision radius margin, colliders
    "coat": (14.0, 5.0, 2.2, 0.035, ("thigh.L", "thigh.R", "shin.L", "shin.R", "torso")),
    "cape": (5.0, 4.0, 2.6, 0.04, ("torso", "upper_arm.L")),
    "pony": (16.0, 5.0, 1.6, 0.03, ("torso", "headball")),
    "plume": (40.0, 7.0, 1.2, 0.0, ()),
}
CAPSULE_R = {"thigh.L": 0.08, "thigh.R": 0.08, "shin.L": 0.06, "shin.R": 0.06, "upper_arm.L": 0.06}


class Sim:
    def __init__(self, R):
        self.R = R
        self.state = {}

    def _targets(self, M, name):
        pts, parent, _ = self.R.chains[name]
        d = M[parent] @ self.R.irest[parent]
        return [d @ q for q in pts]

    def colliders(self, M):
        R = self.R
        out = {}
        for b, r in CAPSULE_R.items():
            h = M[b].translation
            out[b] = (h, h + M[b].col[1].xyz * R.length[b], r)
        hips = M["hips"].translation
        chest_t = M["chest"].translation + M["chest"].col[1].xyz * R.length["chest"]
        out["torso"] = (hips + V((0, 0, 0.02)), chest_t - V((0, 0, 0.04)), 0.135)
        hc = M["head"] @ R.irest["head"] @ model.head_xf((0.005, 0, 1.595))
        out["headball"] = (hc, hc, 0.12)
        return out

    def step(self, M, dt, wind):
        caps = self.colliders(M)
        for name in self.R.chains:
            key = "coat" if name.startswith("coat") else name
            k_s, k_d, k_drag, margin, cols = CHAIN_SETTINGS[key]
            tg = self._targets(M, name)
            if name not in self.state:
                self.state[name] = ([q.copy() for q in tg], [q.copy() for q in tg])
            cur, prev = self.state[name]
            ks = 1 - math.exp(-k_s * dt)
            keep = math.exp(-k_d * dt)
            new = [tg[0].copy()]
            for i in range(1, len(cur)):
                v = (cur[i] - prev[i]) / dt
                acc = V((0, 0, -9.8)) * 0.6 + (V(wind) - v) * k_drag
                q = cur[i] + (cur[i] - prev[i]) * keep + acc * dt * dt
                q = q + (tg[i] - q) * ks
                new.append(q)
            pts = self.R.chains[name][0]
            for _ in range(2):
                for i in range(1, len(new)):
                    L = (pts[i] - pts[i - 1]).length
                    for c in cols:
                        a, b, r = caps[c]
                        ab = b - a
                        t = 0.0 if ab.length_squared < 1e-9 else max(0.0, min(1.0, (new[i] - a).dot(ab) / ab.length_squared))
                        cpt = a + ab * t
                        dv = new[i] - cpt
                        rr = r + margin
                        if dv.length < rr:
                            new[i] = cpt + (dv.normalized() if dv.length > 1e-6 else V((-1, 0, 0))) * rr
                    d = new[i] - new[i - 1]
                    new[i] = new[i - 1] + d.normalized() * L
            self.state[name] = (new, cur)

    def apply(self, M):
        for name, (pts, parent, bones) in self.R.chains.items():
            cur = self.state[name][0]
            for i, b in enumerate(bones):
                M[b] = basis(cur[i], cur[i + 1] - cur[i], M[b].col[2].xyz)


# ------------------------------------------------------------------------------- effects ---

def _fx_material(name, rgb, strength, fade, alpha=1.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    try:
        m.surface_render_method = "BLENDED"
    except AttributeError:
        m.blend_method = "BLEND"
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = model.srgb(*rgb)
    em.inputs[1].default_value = strength
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    if fade:      # alpha from the UV: u = age (0 new .. 1 old), v = across (0 hilt .. 1 tip)
        uv = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(uv.outputs["UV"], sep.inputs[0])
        inv = nt.nodes.new("ShaderNodeMath")
        inv.operation = "SUBTRACT"
        inv.inputs[0].default_value = 1.0
        nt.links.new(sep.outputs[0], inv.inputs[1])
        pw = nt.nodes.new("ShaderNodeMath")
        pw.operation = "POWER"
        pw.inputs[1].default_value = 1.6
        nt.links.new(inv.outputs[0], pw.inputs[0])
        edge = nt.nodes.new("ShaderNodeMapRange")
        edge.inputs[1].default_value = 0.0
        edge.inputs[2].default_value = 0.35
        nt.links.new(sep.outputs[1], edge.inputs[0])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        nt.links.new(pw.outputs[0], mul.inputs[0])
        nt.links.new(edge.outputs[0], mul.inputs[1])
        mul2 = nt.nodes.new("ShaderNodeMath")
        mul2.operation = "MULTIPLY"
        mul2.inputs[1].default_value = 0.85 * alpha
        nt.links.new(mul.outputs[0], mul2.inputs[0])
        nt.links.new(mul2.outputs[0], mix.inputs[0])
    else:
        mix.inputs[0].default_value = alpha
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    return m


def fx_object(rig, name, verts, faces, material, uvs=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    if uvs:
        layer = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            for li in poly.loop_indices:
                layer.data[li].uv = uvs[me.loops[li].vertex_index]
    me.materials.append(material)
    ob = bpy.data.objects.new(name, me)
    model.COLLECTION.objects.link(ob)
    ob.parent = rig
    ob.visible_shadow = False
    return ob


def trail_geo(samples):
    verts, faces, uvs = [], [], []
    n = len(samples)
    for i, (base, tip) in enumerate(samples):
        u = 1.0 - i / (n - 1)
        verts += [base, tip]
        uvs += [(u, 0.0), (u, 1.0)]
    for i in range(n - 1):
        a = 2 * i
        faces.append((a, a + 2, a + 3, a + 1))
    return verts, faces, uvs


def star_geo(center, axis, radius, points=8, inner=0.35, spike=0.0, twist=0.0):
    axis = axis.normalized()
    side = axis.cross(V((0, 0, 1)))
    if side.length < 1e-4:
        side = axis.cross(V((0, 1, 0)))
    side.normalize()
    up = side.cross(axis)
    verts = [center.copy()]
    for k in range(points * 2):
        a = math.pi * k / points + twist
        r = radius if k % 2 == 0 else radius * inner
        verts.append(center + (side * math.cos(a) + up * math.sin(a)) * r)
    faces = [(0, 1 + k, 1 + (k + 1) % (points * 2)) for k in range(points * 2)]
    if spike:
        tip = len(verts)
        verts.append(center + axis * spike)
        w = radius * 0.3
        b0 = len(verts)
        for k in range(4):
            a = math.pi / 2 * k
            verts.append(center + (side * math.cos(a) + up * math.sin(a)) * w)
        faces += [(b0 + k, b0 + (k + 1) % 4, tip) for k in range(4)]
    return verts, faces


def bolt_geo(a, b, seed, width=0.012, segs=7, jag=0.05):
    import random
    rnd = random.Random(seed)
    d = b - a
    side = d.cross(V((0, 0, 1)))
    if side.length < 1e-4:
        side = V((0, 1, 0))
    side.normalize()
    up = side.cross(d.normalized())
    pts = [a + d * (i / segs) + (side * rnd.uniform(-jag, jag) + up * rnd.uniform(-jag, jag)) * (0 < i < segs) for i in range(segs + 1)]
    verts, faces = [], []
    for i, q in enumerate(pts):
        verts += [q + up * width, q - up * width]
    for i in range(segs):
        faces.append((2 * i, 2 * i + 2, 2 * i + 3, 2 * i + 1))
    return verts, faces
