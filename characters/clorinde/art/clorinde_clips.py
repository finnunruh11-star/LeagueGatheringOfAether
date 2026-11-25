"""Clorinde's animation clips: key poses per frame (see clorinde_anim.NEUTRAL for the parameters).

Hand positions are in rig space but carried along with the chest's translation, so a hand at
(0.4, 0.1, 1.2) stays in front of her while she bobs, crouches or lunges.
Every one-shot starts and ends on its stance (STAND with the sword, VREADY with the pistol drawn),
so cross-fades into idle are seamless.
"""
from clorinde_anim import pose

HOLSTER_GRIP = (-0.07, 0.205, 0.935)
HOLSTER_AIM = (-0.41, 0.11, -0.91)


class Clip:
    def __init__(self, name, frames, fps, keys, loop=False, hit=None, land=None, pistol=0, trail=(), fx=None, extra=None,
                 stride=0.0):
        self.name, self.frames, self.fps, self.loop = name, frames, fps, loop
        self.keys = [(k[0], k[1], k[2] if len(k) > 2 else 1.0) for k in keys]
        self.hit, self.land = hit, land
        self.pistol = pistol if isinstance(pistol, list) else [(0, pistol)]     # [(from frame, 0/1)]
        self.trail = list(trail)                                                # [(t0, t1)] sword trail recording
        self.fx = fx or {}                                                      # {frame: [effect names]}
        self.extra = extra or {}
        self.stride = stride                                                    # meters per loop (run cycles)

    def pistol_at(self, f):
        v = 0
        for t, x in self.pistol:
            if f >= t:
                v = x
        return v

    def trail_at(self, t):
        return any(a <= t <= b for a, b in self.trail)


# ------------------------------------------------------------------------------ stances ---

STAND = pose(
    body=(-0.012, 0.014, -0.03),
    hips=(14, 2, -3), spine=(-3, 1, 1), chest=(5, 0, 2), neck=(-7, 0, 0), head=(-9, -3, 3),
    footL=(-0.07, 0.15, 0.085), fyawL=30, footR=(0.1, -0.085, 0.085), fyawR=-4,
    handR=(0.15, -0.27, 0.87), aimR=(0.62, -0.42, -0.66), elbowR=(-0.7, -0.6, -0.3),
    handL=(-0.07, 0.22, 0.99), aimL=(-0.2, 0.3, -0.93), elbowL=(-0.2, 1.0, 0.1), rollL=0.0,
)

VREADY = pose(
    STAND,
    body=(0.0, -0.01, -0.06),
    hips=(-10, 3, -2), spine=(-4, 2, 0), chest=(-10, 1, 0), neck=(8, 0, 0), head=(12, -2, 0),
    footL=(0.13, 0.12, 0.085), fyawL=6, footR=(-0.12, -0.14, 0.085), fyawR=-32,
    handL=(0.38, 0.13, 1.17), aimL=(1.0, -0.06, -0.08), elbowL=(-0.2, 0.8, -0.7),
    handR=(0.0, -0.3, 0.92), aimR=(0.45, -0.58, -0.68), elbowR=(-0.7, -0.6, -0.2),
)


def stance(vigil):
    return VREADY if vigil else STAND


def V_(name, vigil):
    return name + ("@vigil" if vigil else "")


# ---------------------------------------------------------------------------- idle/run ---

def idle():
    b = STAND
    k1 = pose(b, body=(-0.016, 0.016, -0.042), chest=(5, -2, 2), shL=(2.5, 0), shR=(2.5, 0), head=(-8, -1, 4),
              aimR=(0.66, -0.4, -0.63), handR=(0.155, -0.27, 0.865), handL=(-0.07, 0.22, 0.985))
    return Clip("idle", 20, 10, [(0, b), (10, k1)], loop=True)


def idle_vigil():
    b = VREADY
    k1 = pose(b, body=(0.0, -0.01, -0.072), chest=(-10, -1.5, 0), shL=(2, 0), shR=(2, 0), head=(12, -1, 1),
              handL=(0.375, 0.13, 1.155), aimL=(1.0, -0.06, -0.12))
    return Clip("idle@vigil", 16, 10, [(0, b), (8, k1)], loop=True, pistol=1, fx={3: ["spark_pistol"], 11: ["spark_pistol"]})


RUN_L = [  # left ankle (x, z, toe pitch) over the 12 frame cycle; the right foot is half a cycle later
    (0.42, 0.085, 10), (0.22, 0.085, 0), (0.02, 0.085, 0), (-0.18, 0.09, -4), (-0.38, 0.12, -28), (-0.48, 0.22, -48),
    (-0.44, 0.34, -55), (-0.26, 0.42, -35), (0.04, 0.39, -8), (0.31, 0.29, 8), (0.45, 0.18, 16), (0.47, 0.11, 14)]
RUN_Z = [-0.05, -0.08, -0.065, -0.035, -0.012, 0.0]


def run(vigil):
    keys = []
    for f in range(12):
        lx, lz, lt = RUN_L[f]
        rx, rz, rt = RUN_L[(f + 6) % 12]
        ph = 1.0 if f < 6 else -1.0                    # +1 while the left leg is in front
        import math
        c = math.cos(f / 12 * 2 * math.pi)             # +1 at frame 0 (left foot forward), -1 at frame 6
        p = pose(
            body=(0.02, 0.012 * c, RUN_Z[f % 6] - 0.01), hips=(-11 * c, 9, 2 * c), spine=(5 * c, 5, 0), chest=(15 * c, 6, -1 * c),
            neck=(-5 * c, -8, 0), head=(-4 * c, -9, 0),
            footL=(lx, 0.1, lz), toeL=lt, footR=(rx, -0.1, rz), toeR=rt, fyawL=4, fyawR=-4,
            kneeL=(1, 0.1, -0.2), kneeR=(1, -0.1, -0.2),
            wind=(-6.5, 0, 0))
        if vigil:
            p = pose(p, handL=(0.2 + 0.08 * -c, 0.22, 1.08 + 0.04 * -c), aimL=(1.0, 0.05, -0.35), elbowL=(-0.5, 0.7, -0.4))
        else:
            p = pose(p, handL=(0.02 - 0.24 * c, 0.24, 1.04 + 0.1 * -c), aimL=(0.3 - 0.6 * c, 0.1, -0.6 + 0.6 * -c),
                     elbowL=(-0.8, 0.5, -0.2))
        p = pose(p, handR=(-0.02 + 0.14 * c, -0.28, 0.98 + 0.03 * c), aimR=(-0.55, -0.35, -0.75), elbowR=(-0.8, -0.5, -0.2))
        keys.append((f, p))
    return Clip(V_("run", vigil), 12, 18, keys, loop=True, pistol=int(vigil), stride=0.2 * 12)


# ----------------------------------------------------------------------------- attacks ---

def attack_thrust():
    b = STAND
    coil = pose(b, body=(-0.07, 0.0, -0.07), hips=(-6, 0, 0), spine=(-2, -2, 0), chest=(-12, -4, 0), neck=(8, 0, 0), head=(10, 0, 0),
                handR=(-0.06, -0.27, 1.12), aimR=(1, 0.06, 0.1), elbowR=(-1, -0.4, -0.2),
                handL=(-0.18, 0.3, 1.22), aimL=(-0.1, 0.3, 0.95), elbowL=(-0.3, 1, -0.2),
                footR=(0.12, -0.085, 0.12), toeR=12)
    coil2 = pose(coil, body=(-0.09, 0.0, -0.08), handR=(-0.1, -0.26, 1.13))
    hit = pose(b, body=(0.2, -0.02, -0.15), hips=(24, 10, 0), spine=(4, 4, 0), chest=(14, 4, 0), neck=(-16, -6, 0), head=(-16, -6, 0),
               footR=(0.56, -0.085, 0.085), toeR=8, fyawR=0, footL=(-0.24, 0.17, 0.085), fyawL=48,
               handR=(0.74, -0.07, 1.2), aimR=(1, 0.06, 0.02), elbowR=(-0.2, -1, -0.4),
               handL=(-0.4, 0.34, 1.3), aimL=(-0.4, 0.4, 0.8), elbowL=(-0.2, 1, -0.4), wind=(-3, 0, 0))
    over = pose(hit, body=(0.22, -0.02, -0.16), handR=(0.77, -0.07, 1.19))
    back = pose(hit, body=(0.1, -0.0, -0.1), hips=(14, 5, 0), handR=(0.45, -0.18, 1.05), aimR=(0.9, -0.1, -0.3),
                footR=(0.3, -0.085, 0.085), handL=(-0.2, 0.3, 1.1), wind=(0, 0, 0))
    return Clip("attack", 14, 20, [(0, b), (3, coil, 0.6), (5, coil2, 0), (6, hit), (7, over, 0.3), (9, back), (13, b, 0)],
                hit=6, trail=[(4.6, 7.6)])


def attack_slash():
    b = STAND
    wind_up = pose(b, body=(-0.04, 0.02, -0.06), hips=(-12, 0, 0), chest=(-20, -6, 4), neck=(10, 0, 0), head=(14, 0, 0),
                   handR=(-0.12, -0.3, 1.52), aimR=(-0.2, -0.35, 0.92), elbowR=(0, -1, 0.4),
                   handL=(0.22, 0.24, 1.2), aimL=(1, 0, 0.2), elbowL=(-0.3, 0.7, -0.6), footR=(0.12, -0.085, 0.11), toeR=10)
    wind_up2 = pose(wind_up, chest=(-24, -7, 5), handR=(-0.16, -0.28, 1.55))
    hit = pose(b, body=(0.12, -0.01, -0.11), hips=(16, 6, 0), spine=(4, 3, 0), chest=(20, 8, -4), neck=(-14, -4, 0), head=(-16, -4, 0),
               handR=(0.52, -0.1, 1.2), aimR=(0.75, 0.55, -0.35), elbowR=(-0.3, -1, -0.3),
               handL=(-0.25, 0.32, 1.15), aimL=(-0.3, 0.3, -0.9), elbowL=(-0.3, 1, 0),
               footR=(0.42, -0.1, 0.085), footL=(-0.12, 0.16, 0.085), fyawL=40)
    follow = pose(hit, chest=(30, 10, -4), handR=(0.34, 0.2, 0.96), aimR=(0.1, 0.85, -0.52), elbowR=(0.2, -1, -0.5))
    back = pose(follow, body=(0.05, 0.0, -0.07), hips=(10, 3, -2), chest=(12, 4, 0), handR=(0.32, -0.12, 0.92),
                aimR=(0.6, 0.0, -0.8))
    return Clip("attack#slash", 14, 20, [(0, b), (3, wind_up, 0.6), (4, wind_up2, 0), (5, hit), (6, follow, 0.5), (9, back), (13, b, 0)],
                hit=5, trail=[(3.6, 7.0)])


def attack_vigil():
    b = VREADY
    aim = pose(b, handL=(0.43, 0.12, 1.25), aimL=(1, -0.03, 0.0), chest=(-11, 1, 0))
    fire = pose(aim, chest=(-12, 0, 0))
    recoil = pose(aim, handL=(0.35, 0.13, 1.37), aimL=(0.75, -0.02, 0.62), chest=(-8, -4, 0), head=(12, -5, 0),
                  body=(-0.03, -0.01, -0.06))
    settle = pose(b, handL=(0.39, 0.13, 1.24), aimL=(1, -0.05, 0.12))
    return Clip("attack@vigil", 10, 24, [(0, b), (1, aim, 0.3), (2, fire, 0), (3, recoil, 0.4), (5, settle), (9, b, 0)],
                hit=2, pistol=1, fx={2: ["muzzle"], 3: ["muzzle_small", "smoke"]})


# ------------------------------------------------------------------- vigil transitions ---

def cast_e():
    b, e = STAND, VREADY
    reach = pose(b, chest=(8, 2, 7), head=(0, 10, 6), handL=HOLSTER_GRIP, aimL=HOLSTER_AIM, elbowL=(-0.6, 1, 0.2), body=(-0.01, 0.02, -0.05))
    up = pose(e, handL=(0.08, 0.28, 1.47), aimL=(0.25, 0.1, 0.96), elbowL=(0, 1, -0.4), head=(14, -6, 0), body=(0, 0, -0.04))
    tw1 = pose(up, aimL=(-0.4, 0.3, 0.86))
    tw2 = pose(up, handL=(0.18, 0.25, 1.4), aimL=(-0.3, 0.2, -0.93))
    snap = pose(e, handL=(0.44, 0.12, 1.22), aimL=(1, -0.04, 0.02), body=(0.02, -0.01, -0.08))
    return Clip("cast_e", 14, 20, [(0, b), (2, reach, 0.3), (3, reach, 0), (5, up), (6, tw1), (7, tw2), (8, snap, 0), (13, e, 0)],
                pistol=[(0, 0), (3, 1)], fx={8: ["spark_burst"], 9: ["spark_pistol"]})


def exit_vigil():
    b, e = VREADY, STAND
    up = pose(b, handL=(0.12, 0.27, 1.42), aimL=(0.1, 0.1, 1.0), elbowL=(0, 1, -0.4))
    tw = pose(up, aimL=(-0.7, 0.3, 0.4))
    hol = pose(e, chest=(8, 2, 7), head=(0, 8, 6), handL=HOLSTER_GRIP, aimL=HOLSTER_AIM, elbowL=(-0.6, 1, 0.2), body=(-0.01, 0.02, -0.05))
    return Clip("exit@vigil", 10, 18, [(0, b), (2, up), (3, tw), (5, hol, 0.3), (6, hol, 0), (9, e, 0)], pistol=[(0, 1), (6, 0)])


def lunge():
    b = VREADY
    coil = pose(b, body=(-0.07, 0.02, -0.13), hips=(-24, 6, 0), spine=(-4, 4, 0), chest=(-16, 6, 0), neck=(14, 0, 0), head=(24, -4, 0),
                handR=(-0.25, -0.24, 1.08), aimR=(1, 0.0, 0.06), elbowR=(-1, -0.3, -0.2),
                handL=(0.3, 0.2, 1.17), aimL=(1, 0, -0.1),
                footR=(-0.14, -0.12, 0.085), footL=(0.18, 0.14, 0.085))
    launch = pose(b, body=(0.15, 0.0, -0.1), hips=(12, 18, 0), spine=(4, 6, 0), chest=(18, 8, 0), neck=(-12, -10, 0), head=(-16, -8, 0),
                  handR=(0.66, -0.07, 1.12), aimR=(1, 0.04, -0.02), elbowR=(-0.2, -1, -0.4),
                  handL=(-0.36, 0.3, 1.16), aimL=(-1, 0.2, -0.2), elbowL=(0, 1, -0.3),
                  footR=(0.5, -0.1, 0.2), toeR=20, footL=(-0.45, 0.14, 0.2), toeL=-40, fyawR=0, fyawL=10, wind=(-15, 0, 0))
    fly = pose(launch, body=(0.2, 0.0, -0.08), footR=(0.56, -0.1, 0.24), footL=(-0.5, 0.14, 0.27), handR=(0.72, -0.06, 1.13))
    land = pose(fly, body=(0.24, 0.0, -0.17), hips=(14, 22, 0), footR=(0.58, -0.1, 0.085), toeR=0, footL=(-0.42, 0.15, 0.085), toeL=-35,
                handR=(0.76, -0.05, 1.12), wind=(-4, 0, 0))
    hold = pose(land, body=(0.2, 0.0, -0.15), handR=(0.7, -0.08, 1.1), aimR=(0.95, 0, -0.2), wind=(0, 0, 0))
    rise = pose(b, body=(0.1, 0.0, -0.1), handR=(0.3, -0.25, 1.0), aimR=(0.7, -0.4, -0.5), footR=(0.25, -0.1, 0.085), footL=(-0.2, 0.14, 0.085))
    return Clip("cast_e_recast", 14, 20, [(0, b), (1, coil, 0), (2, launch), (4, fly), (6, land, 0), (8, hold), (10, rise), (13, b, 0)],
                hit=2, land=6, pistol=1, trail=[(1.6, 7.2)], fx={2: ["streak", "spark_blade"], 3: ["streak", "spark_blade"], 4: ["streak"],
                                                                5: ["streak", "spark_blade"]})


# --------------------------------------------------------------------------- abilities ---

def cast_q(vigil):
    b = stance(vigil)
    keys = [(0, b)]
    fx = {4: ["flashbang"], 5: ["flashbang_fade", "muzzle"]}
    pistol = 1
    t = 0
    if not vigil:
        reach = pose(b, chest=(8, 2, 7), handL=HOLSTER_GRIP, aimL=HOLSTER_AIM, elbowL=(-0.6, 1, 0.2), body=(-0.01, 0.02, -0.05))
        keys.append((2, reach, 0))
        pistol = [(0, 0), (2, 1), (14, 0)]
    braced = pose(VREADY, body=(0.0, -0.01, -0.1), hips=(-14, 4, -2), chest=(-14, 2, 0), head=(16, -2, 0),
                  handL=(0.44, 0.12, 1.28), aimL=(1, -0.03, 0.05), elbowL=(-0.2, 0.8, -0.6), footL=(0.16, 0.13, 0.085), footR=(-0.16, -0.15, 0.085))
    keys.append((4, braced, 0))
    for i, f in enumerate(range(5, 10)):
        a = 0.5 - 0.25 * i                     # sweep the fan from left to right
        import math
        ang = a * 1.05
        keys.append((f, pose(braced, handL=(0.12 + 0.32 * math.cos(ang), 0.12 + 0.32 * math.sin(ang), 1.28),
                             aimL=(math.cos(ang), math.sin(ang), 0.04), chest=(-14 + 18 * a, 2, 0), hips=(-14 + 8 * a, 4, -2)), 1.0))
        fx.setdefault(f, []).append("muzzle_small" if i % 2 else "muzzle")
    fx[10] = ["smoke"]
    lower = pose(braced, handL=(0.36, 0.16, 1.18), aimL=(0.9, 0, -0.3), body=(0, -0.01, -0.07))
    keys.append((11, lower))
    if vigil:
        keys.append((15, b, 0))
    else:
        hol = pose(STAND, chest=(8, 2, 7), handL=HOLSTER_GRIP, aimL=HOLSTER_AIM, elbowL=(-0.6, 1, 0.2), body=(-0.01, 0.02, -0.05))
        keys += [(13, hol, 0.3), (14, hol, 0), (16, b, 0)]
    n = 16 if vigil else 17
    return Clip(V_("cast_q", vigil), n, 20, keys, pistol=pistol, fx=fx)


def cast_w(vigil):
    b = stance(vigil)
    guard = pose(b, body=(-0.04, 0.0, -0.11), hips=(22, 4, 0), spine=(4, 0, 0), chest=(14, 0, 0), neck=(-16, 0, 0), head=(-20, 0, 0),
                 handR=(0.3, -0.1, 1.3), aimR=(0.22, 0.12, 0.97), elbowR=(0.1, -1, -0.6), rollR=0,
                 footR=(0.25, -0.06, 0.085), fyawR=0, footL=(-0.25, 0.16, 0.085), fyawL=60)
    if vigil:
        guard = pose(guard, handL=(0.02, 0.32, 1.02), aimL=(0.5, 0.3, -0.81), elbowL=(-0.6, 1, 0))
    else:
        guard = pose(guard, handL=(-0.24, 0.12, 1.02), aimL=(0, -0.3, -0.95), elbowL=(-0.3, 1, 0.3))
    settle = pose(guard, body=(-0.05, 0.0, -0.115))
    breathe = pose(guard, body=(-0.05, 0.0, -0.125), aimR=(0.28, 0.1, 0.95), chest=(14, 1.5, 0))
    draw = pose(guard, body=(-0.09, 0.0, -0.12), handR=(0.04, -0.2, 1.2), aimR=(1, 0.02, 0.1), elbowR=(-1, -0.4, -0.2), chest=(4, -2, 0))
    thrust = pose(guard, body=(0.26, -0.02, -0.17), hips=(28, 12, 0), spine=(4, 4, 0), chest=(16, 6, 0), neck=(-18, -8, 0), head=(-20, -8, 0),
                  handR=(0.8, -0.05, 1.2), aimR=(1, 0.04, 0.0), elbowR=(-0.2, -1, -0.4),
                  footR=(0.6, -0.08, 0.085), footL=(-0.28, 0.17, 0.085), fyawL=50, wind=(-4, 0, 0))
    if not vigil:
        thrust = pose(thrust, handL=(-0.42, 0.34, 1.3), aimL=(-0.4, 0.4, 0.8), elbowL=(-0.2, 1, -0.4))
    hold = pose(thrust, body=(0.25, -0.02, -0.16), handR=(0.78, -0.06, 1.19), wind=(0, 0, 0))
    back = pose(thrust, body=(0.1, 0, -0.1), hips=(14, 5, 0), handR=(0.42, -0.2, 1.02), aimR=(0.8, -0.2, -0.5), footR=(0.3, -0.085, 0.085),
                wind=(0, 0, 0))
    keys = [(0, b), (2, guard, 0.5), (3, settle, 0), (8, breathe), (13, settle, 0), (14, draw, 0), (15, thrust), (17, hold, 0.3),
            (19, back), (23, b, 0)]
    return Clip(V_("cast_w", vigil), 24, 20, keys, pistol=int(vigil), trail=[(13.8, 16.4)], fx={3: ["glint"], 9: ["glint"]})


def cast_r(vigil):
    import math
    b = stance(vigil)
    crouch = pose(VREADY, body=(0.0, 0.0, -0.17), hips=(0, 10, 0), chest=(0, 8, 0), head=(0, -4, 0),
                  handR=(-0.22, -0.3, 1.0), aimR=(-0.4, -0.5, -0.76), handL=(0.3, 0.22, 1.18), aimL=(1, 0.2, 0.1),
                  footL=(0.12, 0.16, 0.085), footR=(-0.12, -0.17, 0.085))
    spin = pose(crouch, body=(0.0, 0.0, -0.08), hips=(0, 4, 0), chest=(0, 2, 0), head=(0, 0, 0),
                handR=(0.05, -0.6, 1.25), aimR=(0.25, -1, 0.05), elbowR=(-0.5, -0.2, -1),
                handL=(-0.05, 0.6, 1.25), aimL=(-0.2, 1, 0.0), elbowL=(-0.5, 0.2, -1),
                footL=(0.0, 0.14, 0.085), footR=(0.0, -0.14, 0.085))
    keys = [(0, b)]
    pistol = 1
    if not vigil:
        reach = pose(b, chest=(8, 2, 7), handL=HOLSTER_GRIP, aimL=HOLSTER_AIM, elbowL=(-0.6, 1, 0.2), body=(-0.01, 0.02, -0.05))
        keys.append((1, reach, 0))
        pistol = [(0, 0), (1, 1), (22, 0)]
    keys.append((3, crouch, 0))
    for i in range(1, 7):
        f = 3 + i * 2
        keys.append((f, pose(spin, rot=(0, 0, 60 * i), body=(0, 0, -0.06 + 0.02 * math.sin(i)))))
    salute = pose(STAND if not vigil else VREADY, body=(0.0, 0.0, -0.05), hips=(8, 0, 0), chest=(6, -2, 0), head=(-4, -4, 0),
                  handR=(0.2, -0.06, 1.5), aimR=(0.15, 0.0, 1.0), elbowR=(0.2, -1, -0.4), rot=(0, 0, 360))
    if vigil:
        salute = pose(salute, handL=(0.18, 0.3, 1.0), aimL=(0.2, 0.3, -0.93))
    else:
        salute = pose(salute, handL=HOLSTER_GRIP, aimL=HOLSTER_AIM, elbowL=(-0.6, 1, 0.2))
    keys += [(17, salute, 0), (19, pose(salute, body=(0, 0, -0.055)), 0), (23, pose(b, rot=(0, 0, 360)), 0)]
    fx = {f: ["muzzle"] for f in (5, 7, 9, 11, 13, 15)}
    for f in (4, 6, 8, 10, 12, 14):
        fx[f] = ["muzzle_small"]
    fx[17] = ["glint"]
    return Clip(V_("cast_r", vigil), 24, 20, keys, pistol=pistol, trail=[(3.5, 16.0)], fx=fx)


# ------------------------------------------------------------------------- reactions ---

def hurt(vigil):
    b = stance(vigil)
    hit = pose(b, body=(b["body"][0] - 0.08, b["body"][1], b["body"][2] - 0.02), spine=(0, -6, 0), chest=(b["chest"][0], -14, -5),
               head=(b["head"][0] + 6, -14, 8), shL=(6, 0), shR=(6, 0))
    if vigil:
        hit = pose(hit, handL=(0.3, 0.16, 1.24), aimL=(0.8, 0, 0.5))
    else:
        hit = pose(hit, handR=(0.12, -0.32, 1.02), aimR=(0.5, -0.5, -0.7), handL=(-0.1, 0.3, 1.08))
    return Clip(V_("hurt", vigil), 8, 20, [(0, b), (1, hit, 0), (3, pose(hit, body=(hit["body"][0] + 0.02, hit["body"][1], hit["body"][2]))), (7, b, 0)],
                pistol=int(vigil))


def stun():
    b = STAND
    slump = pose(b, body=(-0.02, 0.0, -0.12), hips=(4, 6, 0), spine=(0, 8, 0), chest=(0, 10, 0), neck=(0, 10, 0), head=(-4, 16, 0),
                 handR=(0.15, -0.26, 0.76), aimR=(0.4, -0.2, -0.9), handL=(0.0, 0.25, 0.82), aimL=(0, 0.2, -1), elbowL=(-0.8, 0.5, 0))
    a = pose(slump, chest=(0, 10, 4), head=(-4, 16, 10), body=(-0.02, 0.025, -0.12))
    c = pose(slump, chest=(0, 10, -4), head=(-4, 16, -10), body=(-0.02, -0.025, -0.125))
    return Clip("stun", 14, 10, [(0, b), (3, slump, 0.5), (4, a), (9, c), (14, a)], extra={"loop_from": 4})


def death():
    b = STAND
    hit = pose(b, body=(-0.1, 0.0, -0.05), spine=(0, -10, 0), chest=(5, -16, -6), head=(-4, -20, 10),
               handR=(0.05, -0.36, 1.08), aimR=(0.3, -0.6, -0.7), handL=(-0.1, 0.34, 1.12))
    buckle = pose(b, body=(-0.12, 0.0, -0.22), hips=(4, -6, 0), spine=(0, -8, 0), chest=(0, -10, -4), neck=(0, -6, 0), head=(-6, -14, 8),
                  footL=(-0.02, 0.15, 0.085), footR=(0.12, -0.1, 0.085), kneeL=(1, 0.3, 0), kneeR=(1, -0.3, 0),
                  handR=(0.1, -0.46, 1.0), aimR=(0.4, -0.7, -0.6), elbowR=(-0.3, -1, 0),
                  handL=(-0.05, 0.46, 1.04), aimL=(0, 0.5, -0.86), elbowL=(-0.3, 1, 0))
    tip = pose(buckle, rot=(0, -40, 0), pivot=(-0.12, 0, 0), body=(-0.08, 0.0, -0.12), head=(-8, -18, 8),
               handR=(0.0, -0.5, 1.2), aimR=(0.3, -0.9, 0.2), handL=(0.0, 0.5, 1.22), aimL=(0.2, 0.9, 0.2))
    lying = pose(b, rot=(0, -86, 0), pivot=(-0.14, 0, 0), move=(0, 0, 0.03), body=(0, 0, 0), hips=(0, 0, 0), spine=(0, 0, 0),
                 chest=(0, 0, 0), neck=(0, 0, 0), head=(28, -6, 0),
                 footL=(0.03, 0.16, 0.085), fyawL=20, footR=(0.06, -0.13, 0.13), fyawR=-10, kneeR=(1, -0.2, 0.3),
                 handR=(-0.2, -0.56, 1.22), aimR=(0.0, -0.8, -0.6), elbowR=(-0.2, -1, -0.6),
                 handL=(-0.2, 0.52, 1.34), aimL=(0.0, 0.9, -0.3), elbowL=(-0.2, 1, -0.6))
    bounce = pose(lying, rot=(0, -80, 0), move=(0, 0, 0.05))
    return Clip("death", 20, 14, [(0, b), (2, hit, 0), (5, buckle, 0.5), (8, tip), (11, lying, 0), (12, bounce, 0), (14, lying, 0),
                                  (19, lying, 0)])


def spawn():
    b = STAND
    kneel = pose(b, body=(-0.05, 0.0, -0.36), hips=(10, 10, 0), spine=(0, 6, 0), chest=(4, 10, 0), neck=(0, 10, 0), head=(-6, 22, 0),
                 footL=(0.26, 0.14, 0.085), fyawL=10, footR=(-0.36, -0.11, 0.1), toeR=-70, kneeR=(1, -0.1, -1),
                 handR=(0.32, -0.15, 0.76), aimR=(0.08, 0.0, -1), elbowR=(-0.4, -1, -0.2),
                 handL=(0.24, 0.18, 0.66), aimL=(0.5, 0.0, -0.86), elbowL=(-0.2, 1, 0.3))
    rise = pose(b, body=(-0.02, 0.0, -0.1), head=(-6, 4, 0), chest=(4, 2, 0), handR=(0.3, -0.18, 1.0), aimR=(0.2, 0, -1))
    salute = pose(b, body=(-0.01, 0.0, -0.035), hips=(8, 0, 0), chest=(6, -2, 0), head=(-6, -4, 0),
                  handR=(0.2, -0.06, 1.48), aimR=(0.12, 0.0, 1.0), elbowR=(0.2, -1, -0.4))
    sweep = pose(b, handR=(0.36, -0.36, 0.98), aimR=(0.55, -0.65, -0.52), chest=(-4, 0, 0))
    return Clip("spawn", 18, 15, [(0, kneel), (3, kneel, 0), (8, rise), (10, salute, 0), (12, salute, 0), (14, sweep), (17, b, 0)],
                trail=[(12.5, 15.0)], fx={10: ["glint"]})


def recall():
    rest = pose(STAND, body=(0.0, 0.0, -0.02), hips=(0, 0, 0), spine=(0, 2, 0), chest=(0, 2, 0), neck=(0, 6, 0), head=(0, 12, 0),
                footL=(0.0, 0.13, 0.085), fyawL=12, footR=(0.0, -0.13, 0.085), fyawR=-12,
                handR=(0.25, -0.035, 1.08), aimR=(0.06, 0.02, -1), elbowR=(-0.2, -1, -0.3),
                handL=(0.27, 0.035, 1.12), aimL=(0.2, -0.2, -0.96), elbowL=(-0.2, 1, -0.3))
    b2 = pose(rest, body=(0.0, 0.0, -0.03), chest=(0, 0.5, 0), head=(0, 13, 0), shL=(2, 0), shR=(2, 0))
    return Clip("recall", 16, 8, [(0, rest), (8, b2)], loop=True)


def fidget():
    b = STAND
    reach = pose(b, chest=(8, 2, 7), head=(0, 10, 6), handL=HOLSTER_GRIP, aimL=HOLSTER_AIM, elbowL=(-0.6, 1, 0.2), body=(-0.01, 0.02, -0.05))
    out = pose(b, handL=(0.14, 0.4, 1.16), aimL=(1, 0.2, 0), elbowL=(-0.3, 1, -0.4), head=(14, 6, 0), chest=(10, 0, 0))
    keys = [(0, b), (2, reach, 0.3), (3, reach, 0), (5, out)]
    spin = [(0, 0, -1), (-1, 0, 0), (0, 0, 1), (1, 0.2, 0)]
    for i in range(8):
        keys.append((6 + i, pose(out, aimL=spin[i % 4])))
    up = pose(out, handL=(0.12, 0.3, 1.42), aimL=(0.05, 0.05, 1), head=(16, -4, 0))
    keys += [(15, up, 0), (17, up, 0), (19, reach, 0.3), (20, reach, 0), (23, b, 0)]
    return Clip("fidget", 24, 15, keys, pistol=[(0, 0), (3, 1), (20, 0)], fx={16: ["smoke"]})


def all_clips():
    return [idle(), run(False), attack_thrust(), attack_slash(), idle_vigil(), run(True), attack_vigil(), cast_e(), exit_vigil(), lunge(),
            cast_q(False), cast_q(True), cast_w(False), cast_w(True), cast_r(False), cast_r(True), hurt(False), hurt(True), stun(), death(),
            spawn(), recall(), fidget()]
