# Part of tools/hound/build.sh (see there).
# Stage 2: author the hound's clips on the skinned rig and export GLBs.
# Legs are driven by IK targets (paw on the ground in stance, folded in
# swing), the rest by FK. Each frame is solved, then baked to plain FK keys.
import bpy, sys, math
from mathutils import Vector, Matrix, Quaternion, Euler
args = sys.argv[sys.argv.index("--")+1:]
src, out_model, out_anims = args[0], args[1], args[2]
only = args[3].split(",") if len(args) > 3 and args[3] != "-" else None
bpy.ops.wm.open_mainfile(filepath=src)
FPS = 30
sc = bpy.context.scene
sc.render.fps = FPS
arm = bpy.data.objects["hound_rig"]
ad = arm.data
bpy.context.view_layer.objects.active = arm

def smooth(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)
def lerp(a, b, u):
    return a + (b - a) * u
def bump(u):           # 0..1..0 over u in [0,1]
    return math.sin(math.pi * min(max(u, 0.0), 1.0))
def ease(keys, t):
    """Piecewise smooth interpolation through (time, value) keys."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            u = smooth((t - t0) / (t1 - t0)) if t1 > t0 else 1.0
            if isinstance(v0, (tuple, list)):
                return tuple(lerp(a, b, u) for a, b in zip(v0, v1))
            return lerp(v0, v1, u)
    return keys[-1][1]

LEGS = {}
for s, sx in (("L", 1), ("R", -1)):
    LEGS["f" + s] = {"kind": "f", "sx": sx, "upper": "upperarm_" + s, "lower": "forearm_" + s,
        "mid": "hand_" + s, "end": "fpaw_" + s,
        "W0": Vector((0.088 * sx, -0.278, 0.095)), "P0": Vector((0.105 * sx, -0.325, 0.035)), "T0": Vector((0.12 * sx, -0.39, 0.015))}
    LEGS["h" + s] = {"kind": "h", "sx": sx, "upper": "thigh_" + s, "lower": "shin_" + s,
        "mid": "foot_" + s, "end": "hpaw_" + s,
        "W0": Vector((0.122 * sx, 0.385, 0.175)), "P0": Vector((0.15 * sx, 0.365, 0.04)), "T0": Vector((0.165 * sx, 0.31, 0.015))}

# Control bones (not exported): wrist/hock, paw-ball and toe targets, poles.
bpy.ops.object.mode_set(mode='EDIT')
eb = ad.edit_bones
for k, L in LEGS.items():
    for nm, p in (("W", L["W0"]), ("P", L["P0"]), ("T", L["T0"])):
        b = eb.new("tgt%s_%s" % (nm, k)); b.head = p; b.tail = p + Vector((0, 0, 0.05))
        b.parent = eb["root"]; b.use_deform = False
    pole = L["W0"] + Vector((0, 0.6 if L["kind"] == "f" else -0.6, 0.3))
    b = eb.new("pole_" + k); b.head = pole; b.tail = pole + Vector((0, 0, 0.05))
    b.parent = eb["root"]; b.use_deform = False
bpy.ops.object.mode_set(mode='POSE')
pb = arm.pose.bones
REST = {b.name: b.bone.matrix_local.copy() for b in pb}

def add_ik(k, pole_angle):
    L = LEGS[k]
    for b in (L["lower"], L["mid"], L["end"]):
        for c in list(pb[b].constraints):
            pb[b].constraints.remove(c)
    c = pb[L["lower"]].constraints.new('IK')
    c.target = arm; c.subtarget = "tgtW_" + k
    c.pole_target = arm; c.pole_subtarget = "pole_" + k
    c.pole_angle = pole_angle; c.chain_count = 2
    d = pb[L["mid"]].constraints.new('DAMPED_TRACK'); d.target = arm; d.subtarget = "tgtP_" + k
    d2 = pb[L["end"]].constraints.new('DAMPED_TRACK'); d2.target = arm; d2.subtarget = "tgtT_" + k

def set_tgt(name, p):
    b = pb[name]
    b.matrix_basis = Matrix.Translation(REST[name].inverted().to_3x3() @ (Vector(p) - REST[name].translation))

# Pick each leg's pole angle so the rest stance solves back to the rest pose.
for k, L in LEGS.items():
    best = None
    for ang in range(-180, 180, 5):
        add_ik(k, math.radians(ang))
        for nm in ("W", "P", "T"):
            set_tgt("tgt%s_%s" % (nm, k), L[nm + "0"])
        bpy.context.view_layer.update()
        err = sum(((pb[b].matrix.to_3x3() @ Vector((0, 1, 0))) - (REST[b].to_3x3() @ Vector((0, 1, 0)))).length for b in (L["upper"], L["lower"]))
        if best is None or err < best[0]:
            best = (err, ang)
    add_ik(k, math.radians(best[1]))
    print("pole", k, best)

DEFORM = [b.name for b in pb if b.bone.use_deform]
FKB = ["root", "body"] + DEFORM
WORLD_AXES = {"x": Vector((1, 0, 0)), "y": Vector((0, 1, 0)), "z": Vector((0, 0, 1))}

def fk_quat(name, r):
    """r = (rx, ry, rz) degrees about the rig's world axes in the bone's rest frame."""
    q = Quaternion()
    inv = REST[name].to_3x3().inverted()
    for ax, deg in zip("xyz", r):
        if deg:
            q = Quaternion((inv @ WORLD_AXES[ax]).normalized(), math.radians(deg)) @ q
    return q

def leg_points(k, dy=0.0, dz=0.0, cw=0.0, ct=0.0, dx=0.0):
    L = LEGS[k]
    P = L["P0"] + Vector((dx * L["sx"], dy, dz))
    Rw = Matrix.Rotation(math.radians(cw), 3, 'X')
    Rt = Matrix.Rotation(math.radians(ct), 3, 'X')
    return P + Rw @ (L["W0"] - L["P0"]), P, P + Rt @ (L["T0"] - L["P0"])

def apply_frame(pose):
    """pose: {"fk": {bone: (rx,ry,rz)}, "loc": {bone: (x,y,z)}, "legs": {k: (W,P,T)} or None for FK legs}"""
    for b in FKB:
        pb[b].rotation_mode = 'QUATERNION'
        pb[b].rotation_quaternion = fk_quat(b, pose["fk"].get(b, (0, 0, 0)))
        pb[b].location = (0, 0, 0)
    for b, v in pose.get("loc", {}).items():
        # location given in rig space; convert to the bone's rest frame
        pb[b].location = REST[b].to_3x3().inverted() @ Vector(v)
    legs = pose.get("legs")
    for k, L in LEGS.items():
        on = legs is not None and k in legs
        for b in (L["lower"], L["mid"], L["end"]):
            for c in pb[b].constraints:
                c.influence = 1.0 if on else 0.0
        if on:
            W, P, T = legs[k]
            set_tgt("tgtW_" + k, W); set_tgt("tgtP_" + k, P); set_tgt("tgtT_" + k, T)
    bpy.context.view_layer.update()
    return {b: pb[b].matrix.copy() for b in FKB}

def bake(name, nframes, fn, loop):
    frames = [apply_frame(fn(f / FPS)) for f in range(nframes + (1 if loop else 0))]
    if loop:
        frames[-1] = frames[0]
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    for b in FKB:
        pb[b].rotation_mode = 'QUATERNION'
    for fi, mats in enumerate(frames):
        for b in FKB:
            par = pb[b].parent
            if par is None:
                basis = REST[b].inverted() @ mats[b]
            else:
                basis = (REST[par.name].inverted() @ REST[b]).inverted() @ mats[par.name].inverted() @ mats[b]
            loc, rot, _ = basis.decompose()
            pb[b].location = loc
            pb[b].rotation_quaternion = rot
            pb[b].scale = (1, 1, 1)
            pb[b].keyframe_insert("location", frame=fi)
            pb[b].keyframe_insert("rotation_quaternion", frame=fi)
    # keep quaternion signs continuous
    arm.animation_data.action = None
    act.frame_range = (0, len(frames) - 1)
    act.use_frame_range = True
    print("baked", name, len(frames), "frames")
    return act

# ---------------------------------------------------------------- clips
def stand_legs():
    return {k: leg_points(k) for k in LEGS}

def gait_leg(k, s, D, Ls, lift, fold_w, fold_t, reach_off=0.0):
    """Paw path for phase s (0..1): stance [0,D) slides back, swing lifts forward."""
    L = LEGS[k]
    front = L["kind"] == "f"
    if s < D:
        u = s / D
        dy = -Ls / 2 + Ls * u + reach_off
        # roll over the paw: wrist tips forward late in stance
        cw = lerp(-8, 22, u) if front else lerp(6, -14, u)
        return leg_points(k, dy, 0.0, cw, 0.0)
    u = (s - D) / (1 - D)
    dy = Ls / 2 - Ls * smooth(u) + reach_off
    dz = lift * bump(u) ** 0.8
    if front:
        return leg_points(k, dy, dz, lerp(22, -8, smooth(u)) + fold_w * bump(u), fold_t * bump(u))
    return leg_points(k, dy, dz, lerp(-14, 6, smooth(u)) - fold_w * bump(u), fold_t * bump(u))

def scap(dy):
    return max(-28.0, min(28.0, dy * 75.0))

def clip_walk(t):
    T = 0.9; D = 0.62; Ls = 0.56
    ph = {"hL": 0.0, "fL": 0.25, "hR": 0.5, "fR": 0.75}
    s0 = (t / T) % 1.0
    legs = {}
    fk = {}
    for k, o in ph.items():
        s = (s0 + o) % 1.0
        legs[k] = gait_leg(k, s, D, Ls, 0.07 if k[0] == "f" else 0.06, 55, 70)
        if k[0] == "f":
            fk["scapula_" + k[1]] = (scap(legs[k][1].y - LEGS[k]["P0"].y), 0, 0)
    w = 2 * math.pi * s0
    fk["body"] = (1.5 * math.sin(2 * w), 2.0 * math.sin(w), 1.5 * math.sin(w))
    fk["spine1"] = (0, 0, 2.5 * math.sin(w))
    fk["spine2"] = (0, 0, 2.0 * math.sin(w + 0.4))
    fk["neck1"] = (12 + 3 * math.sin(2 * w + 0.6), 0, -2 * math.sin(w))
    fk["neck2"] = (6, 0, 0)
    fk["head"] = (-6 + 2.5 * math.sin(2 * w + 1.2), 0, 0)
    fk["jaw"] = (6 + 2 * math.sin(2 * w), 0, 0)
    fk["tail1"] = (-18, 0, 10 * math.sin(w))
    fk["tail2"] = (-6, 0, 10 * math.sin(w - 0.7))
    fk["tail3"] = (0, 0, 9 * math.sin(w - 1.4))
    fk["tail4"] = (0, 0, 8 * math.sin(w - 2.1))
    fk["ear_L"] = (-25, 0, 0); fk["ear_R"] = (-25, 0, 0)
    return {"fk": fk, "loc": {"body": (0, 0, -0.015 + 0.012 * math.cos(2 * w))}, "legs": legs}

def clip_trot(t):
    # Diagonal pairs move together, a short float between them.
    T = 0.5; D = 0.45; Ls = 0.56
    ph = {"hL": 0.0, "fR": 0.0, "hR": 0.5, "fL": 0.5}
    s0 = (t / T) % 1.0
    legs = {}; fk = {}
    for k, o in ph.items():
        s = (s0 + o) % 1.0
        legs[k] = gait_leg(k, s, D, Ls, 0.09 if k[0] == "f" else 0.08, 65, 80)
        if k[0] == "f":
            fk["scapula_" + k[1]] = (scap(legs[k][1].y - LEGS[k]["P0"].y), 0, 0)
    w = 2 * math.pi * s0
    fk["body"] = (1.5 * math.sin(2 * w), 2.5 * math.sin(w), 0)
    fk["spine1"] = (0, 0, 2 * math.sin(w))
    fk["neck1"] = (14 + 3 * math.sin(2 * w + 0.8), 0, 0)
    fk["neck2"] = (6, 0, 0)
    fk["head"] = (-6 + 3 * math.sin(2 * w + 1.4), 0, 0)
    fk["jaw"] = (12 + 4 * math.sin(2 * w), 0, 0)
    fk["tail1"] = (-14, 0, 8 * math.sin(w)); fk["tail2"] = (-4, 0, 8 * math.sin(w - 0.7))
    fk["tail3"] = (0, 0, 7 * math.sin(w - 1.4)); fk["tail4"] = (0, 0, 6 * math.sin(w - 2.1))
    fk["ear_L"] = (-35, 0, 0); fk["ear_R"] = (-35, 0, 0)
    return {"fk": fk, "loc": {"body": (0, 0, -0.02 + 0.018 * math.cos(2 * w))}, "legs": legs}

def clip_run(t):
    # Rotary gallop: hinds land, then fronts; back flexes and stretches.
    T = 0.44; D = 0.34; Ls = 0.62
    ph = {"hL": 0.0, "hR": 0.09, "fR": 0.42, "fL": 0.52}
    s0 = (t / T) % 1.0
    legs = {}; fk = {}
    for k, o in ph.items():
        s = (s0 + o) % 1.0
        legs[k] = gait_leg(k, s, D, Ls, 0.15 if k[0] == "f" else 0.13, 80, 95)
        if k[0] == "f":
            fk["scapula_" + k[1]] = (scap(legs[k][1].y - LEGS[k]["P0"].y), 0, 0)
    w = 2 * math.pi * s0
    flex = math.sin(w + 0.9)             # +1 gathered (back arched), -1 stretched
    fk["body"] = (-5 * math.cos(w + 0.3), 0, 0)
    fk["pelvis"] = (-9 * flex, 0, 0)
    fk["spine1"] = (6 * flex, 0, 0)
    fk["spine2"] = (5 * flex, 0, 0)
    fk["chest"] = (3 * flex, 0, 0)
    fk["neck1"] = (16 - 6 * math.sin(w + 0.4), 0, 0)
    fk["neck2"] = (6, 0, 0)
    fk["head"] = (-6 + 5 * math.sin(w + 1.0), 0, 0)
    fk["jaw"] = (16 + 6 * math.sin(w), 0, 0)
    fk["tail1"] = (-8 + 8 * flex, 0, 4 * math.sin(w))
    fk["tail2"] = (2 + 6 * math.sin(w - 0.8), 0, 0)
    fk["tail3"] = (3 + 6 * math.sin(w - 1.6), 0, 0)
    fk["tail4"] = (3 + 6 * math.sin(w - 2.4), 0, 0)
    fk["ear_L"] = (-40, 0, 0); fk["ear_R"] = (-40, 0, 0)
    return {"fk": fk, "loc": {"body": (0, 0.0, -0.035 + 0.035 * math.sin(w + 2.2))}, "legs": legs}

def clip_idle(t):
    T = 4.0; w = 2 * math.pi * t / T
    breath = math.sin(2 * math.pi * t / 1.0)
    fk = {
        "body": (0.8 * breath, 0, 0),
        "chest": (-0.8 * breath, 0, 0),
        "neck1": (12 + 2 * math.sin(w), 0, 6 * math.sin(w + 0.5)),
        "neck2": (0, 0, 8 * math.sin(w + 0.3) + 5 * smooth(math.sin(2 * w) * 0.5 + 0.5) - 2.5),
        "head": (-8 + 3 * math.sin(2 * w), 0, 6 * math.sin(w)),
        "jaw": (5 + 4 * max(0.0, math.sin(4 * w)) + 1.5 * breath, 0, 0),
        "tail1": (-24, 0, 4 * math.sin(w * 2)),
        "tail2": (-8, 0, 4 * math.sin(w * 2 - 0.6)),
        "tail3": (-4, 0, 4 * math.sin(w * 2 - 1.2)),
        "tail4": (0, 0, 4 * math.sin(w * 2 - 1.8)),
        "ear_L": (-30 + 10 * max(0.0, math.sin(3 * w)) ** 8, 0, 0),
        "ear_R": (-30, 0, 0),
    }
    return {"fk": fk, "loc": {"body": (0, 0, -0.01 + 0.004 * breath)}, "legs": stand_legs()}

def clip_feed(t):
    # Head down in a kill, tearing at it. Front legs spread and bent.
    T = 3.0; w = 2 * math.pi * t / T
    tear = max(0.0, math.sin(2 * w)) ** 3
    legs = {
        "fL": leg_points("fL", -0.06, 0, 0, 0, 0.03), "fR": leg_points("fR", -0.03, 0, 0, 0, 0.03),
        "hL": leg_points("hL", 0.02), "hR": leg_points("hR", 0.0),
    }
    fk = {
        "body": (14, 0, 2 * math.sin(w)),
        "scapula_L": (-6, 0, 0), "scapula_R": (-4, 0, 0),
        "spine1": (3, 0, 0), "spine2": (4, 0, 0), "chest": (6, 0, 0),
        "neck1": (34 - 8 * tear, 0, 4 * math.sin(w)),
        "neck2": (22 - 6 * tear, 0, 10 * math.sin(2 * w) * tear),
        "head": (18 - 14 * tear, 10 * math.sin(4 * w) * tear, 6 * math.sin(2 * w)),
        "jaw": (10 + 14 * (1 - tear) * max(0.0, math.sin(3 * w)), 0, 0),
        "tail1": (-26, 0, 3 * math.sin(w)), "tail2": (-10, 0, 3 * math.sin(w - 0.5)),
        "tail3": (-4, 0, 0), "tail4": (0, 0, 0),
        "ear_L": (-15, 0, 0), "ear_R": (-15, 0, 0),
    }
    return {"fk": fk, "loc": {"body": (0, -0.03, -0.09)}, "legs": legs}

# Attacks: the game starts the clip at 1.0 s and the bite lands at 1.5 s.
def clip_lunge(t):
    # 0..1 crouched snarl (rarely seen), 1.0 coil, 1.15 spring, 1.5 snap, land, recover by 2.3.
    by = ease([(0, 0.06), (1.0, 0.07), (1.12, 0.11), (1.38, -0.32), (1.55, -0.36), (1.85, -0.18), (2.3, 0.0)], t)
    bz = ease([(0, -0.07), (1.0, -0.07), (1.12, -0.11), (1.33, 0.10), (1.55, 0.02), (1.8, -0.04), (2.3, 0.0)], t)
    bp = ease([(0, 6), (1.0, 6), (1.12, 5), (1.33, -9), (1.55, 2), (1.8, 5), (2.3, 0)], t)
    fdy = ease([(0, 0.0), (1.12, 0.0), (1.36, -0.66), (1.55, -0.62), (1.9, -0.30), (2.3, 0.0)], t)
    fdz = ease([(0, 0.0), (1.12, 0.0), (1.3, 0.30), (1.45, 0.16), (1.58, 0.0), (1.95, 0.0), (2.08, 0.06), (2.3, 0.0)], t)
    hdy = ease([(0, 0.0), (1.12, 0.03), (1.4, 0.10), (1.65, -0.22), (2.0, -0.12), (2.3, 0.0)], t)
    hdz = ease([(0, 0.0), (1.35, 0.0), (1.5, 0.08), (1.65, 0.0), (2.3, 0.0)], t)
    hcw = ease([(0, 0.0), (1.12, -10), (1.35, -30), (1.5, -10), (1.7, 0), (2.3, 0)], t)
    fcw = ease([(0, 0), (1.12, 0), (1.25, 50), (1.4, 10), (1.55, 0), (2.3, 0)], t)
    jaw = ease([(0, 14), (1.0, 14), (1.15, 18), (1.38, 38), (1.48, 36), (1.53, 2), (1.75, 4), (1.9, 20), (2.3, 8)], t)
    shake = math.sin((t - 1.5) * 34) * max(0.0, 1 - abs(t - 1.68) / 0.18) if t > 1.5 else 0.0
    legs = {
        "fL": leg_points("fL", fdy, fdz, fcw, fcw * 1.3), "fR": leg_points("fR", fdy + 0.05, max(0, fdz - 0.03), fcw, fcw * 1.3),
        "hL": leg_points("hL", hdy, hdz, hcw), "hR": leg_points("hR", hdy + 0.03, hdz, hcw),
    }
    fk = {
        "body": (bp, 0, 0),
        "scapula_L": (scap(fdy) * 0.8, 0, 0), "scapula_R": (scap(fdy) * 0.8, 0, 0),
        "spine1": (ease([(0, 3), (1.12, 5), (1.38, -4), (1.7, 2), (2.3, 0)], t), 0, 0),
        "spine2": (ease([(0, 3), (1.12, 5), (1.38, -3), (1.7, 2), (2.3, 0)], t), 0, 0),
        "neck1": (ease([(0, 16), (1.0, 16), (1.12, 18), (1.36, 2), (1.5, 14), (1.8, 12), (2.3, 10)], t), 0, 8 * shake),
        "neck2": (ease([(0, 8), (1.12, 8), (1.36, 0), (1.5, 10), (2.3, 4)], t), 0, 10 * shake),
        "head": (ease([(0, -10), (1.12, -12), (1.36, 0), (1.5, 16), (1.8, 4), (2.3, -6)], t), 14 * shake, 6 * shake),
        "jaw": (jaw, 0, 0),
        "tail1": (ease([(0, -30), (1.12, -32), (1.38, 4), (1.7, -10), (2.3, -18)], t), 0, 0),
        "tail2": (ease([(0, -10), (1.38, 6), (2.3, -4)], t), 0, 0),
        "tail3": (ease([(0, -4), (1.38, 8), (2.3, 0)], t), 0, 0),
        "tail4": (0, 0, 0),
        "ear_L": (-50, 0, 0), "ear_R": (-50, 0, 0),
    }
    return {"fk": fk, "loc": {"body": (0, by, bz)}, "legs": legs}

def clip_bite(t):
    # Close in: dip, head shoots forward and snaps at 1.5, tears side to side.
    by = ease([(0, 0.03), (1.0, 0.03), (1.2, 0.08), (1.45, -0.20), (1.6, -0.17), (2.0, -0.05), (2.3, 0.0)], t)
    bz = ease([(0, -0.04), (1.0, -0.04), (1.2, -0.07), (1.45, -0.02), (2.3, 0.0)], t)
    jaw = ease([(0, 14), (1.0, 14), (1.2, 22), (1.42, 40), (1.5, 2), (1.95, 4), (2.1, 16), (2.3, 8)], t)
    shake = math.sin((t - 1.5) * 30) * max(0.0, 1 - abs(t - 1.75) / 0.25) if t > 1.5 else 0.0
    fdy = ease([(0, 0.0), (1.2, 0.0), (1.4, -0.16), (1.7, -0.16), (2.3, 0.0)], t)
    fdz = ease([(0, 0.0), (1.2, 0.0), (1.3, 0.07), (1.4, 0.0), (2.3, 0.0)], t)
    legs = {
        "fL": leg_points("fL", fdy, fdz, 0), "fR": leg_points("fR", fdy * 0.5, 0.0, 0),
        "hL": leg_points("hL", 0.02), "hR": leg_points("hR", 0.0),
    }
    fk = {
        "body": (ease([(0, 5), (1.2, 8), (1.45, 4), (2.3, 0)], t), 0, 4 * shake),
        "scapula_L": (scap(fdy), 0, 0), "scapula_R": (scap(fdy * 0.5), 0, 0),
        "spine2": (0, 0, 6 * shake), "chest": (0, 0, 6 * shake),
        "neck1": (ease([(0, 14), (1.2, 22), (1.44, -4), (1.55, 16), (2.3, 10)], t), 0, 10 * shake),
        "neck2": (ease([(0, 8), (1.2, 12), (1.44, -10), (1.55, 10), (2.3, 4)], t), 0, 14 * shake),
        "head": (ease([(0, -10), (1.2, -16), (1.44, -6), (1.55, 18), (2.0, 4), (2.3, -6)], t), 22 * shake, 10 * shake),
        "jaw": (jaw, 0, 0),
        "tail1": (-28, 0, 6 * shake), "tail2": (-8, 0, 6 * shake), "tail3": (-2, 0, 0), "tail4": (0, 0, 0),
        "ear_L": (-50, 0, 0), "ear_R": (-50, 0, 0),
    }
    return {"fk": fk, "loc": {"body": (0, by, bz)}, "legs": legs}

def clip_hit(t):
    # Rocked by a hit: snaps back and to the side, yelps, recovers.
    k = ease([(0, 0), (0.07, 1), (0.25, 0.7), (0.6, 0)], t)
    legs = {"fL": leg_points("fL", 0.04 * k, 0.05 * bump(t / 0.3), 10 * k), "fR": leg_points("fR"), "hL": leg_points("hL"), "hR": leg_points("hR", 0.02 * k)}
    fk = {
        "body": (-6 * k, -6 * k, 7 * k),
        "spine2": (0, 0, -6 * k), "chest": (0, -4 * k, -6 * k),
        "neck1": (-14 * k, 0, -14 * k), "neck2": (-10 * k, 0, -10 * k),
        "head": (-14 * k, 10 * k, -8 * k),
        "jaw": (10 + 22 * k, 0, 0),
        "tail1": (-26 + 6 * k, 0, 0), "tail2": (-6, 0, 0),
        "ear_L": (-55, 0, 0), "ear_R": (-55, 0, 0),
    }
    return {"fk": fk, "loc": {"body": (0, 0.07 * k, -0.03 * k)}, "legs": legs}

def death_side(side):
    # side=+1 rolls over to its right (-X) side, -1 to its left.
    def f(t):
        fold = ease([(0, 0), (0.18, 0.5), (0.45, 1.0)], t)       # legs buckle
        roll = ease([(0, 0), (0.25, 0.0), (0.7, 1.0), (0.82, 0.93), (0.95, 1.0)], t)
        twitch = math.sin(t * 40) * max(0.0, 1 - abs(t - 1.35) / 0.25) * 0.5
        ang = 90 * roll * side
        drop = ease([(0, 0.0), (0.45, -0.24), (0.7, -0.40)], t)
        lift = 0.17 * roll
        fk = {
            "root": (0, ang, 0),
            "body": (ease([(0, 0), (0.3, 8), (0.7, 0)], t), 0, 0),
            "spine1": (0, 0, -6 * roll * side), "spine2": (0, 0, -6 * roll * side), "chest": (0, 0, -4 * roll * side),
            "neck1": (ease([(0, 0), (0.25, -18), (0.7, 10), (1.0, 20)], t), 0, -12 * roll * side),
            "neck2": (ease([(0, 0), (0.25, -10), (0.75, 18), (1.0, 14)], t), 0, -8 * roll * side),
            "head": (ease([(0, 0), (0.25, -16), (0.8, 6)], t), 0, -10 * roll * side),
            "jaw": (ease([(0, 10), (0.2, 36), (0.9, 26), (1.4, 18)], t) + 6 * twitch, 0, 0),
            "tail1": (-30 * (1 - roll), 0, -20 * roll * side), "tail2": (-6, 0, -12 * roll * side), "tail3": (0, 0, -8 * roll * side),
            "ear_L": (-30, 0, 0), "ear_R": (-30, 0, 0),
        }
        for s in ("L", "R"):
            up = (s == "L") == (side > 0)        # upper-side legs flop over, lower ones stretch out
            fk["scapula_" + s] = (-10 * fold, 0, 0)
            fk["upperarm_" + s] = (lerp(0, -30, fold) + (10 * twitch if up else 0), 0, 0)
            fk["forearm_" + s] = (lerp(0, 50, fold) - 22 * roll + (8 if up else 0) * roll, 0, 0)
            fk["hand_" + s] = (lerp(0, -30, fold) + 12 * roll, 0, 0)
            fk["thigh_" + s] = (lerp(0, -40, fold) + 18 * roll - (10 if up else 0) * roll, 0, 0)
            fk["shin_" + s] = (lerp(0, 60, fold) - 25 * roll + (14 * twitch if up else 0), 0, 0)
            fk["foot_" + s] = (lerp(0, -40, fold) + 18 * roll, 0, 0)
        return {"fk": fk, "loc": {"root": (-0.12 * side * roll, 0, max(0.0, lift + drop * (1 - roll))), "body": (0, 0, drop * (1 - roll) * 0.0)}, "legs": None}
    return f

def death_collapse(t):
    # Legs give out mid-stride: drops onto its chest, chin skids, rolls a little.
    fold = ease([(0, 0), (0.25, 1.0)], t)
    sink = ease([(0, 0), (0.12, -0.10), (0.3, -0.36), (0.36, -0.33), (0.45, -0.36)], t)
    pitch = ease([(0, 0), (0.18, 12), (0.3, 6), (0.45, 0)], t)
    roll = ease([(0, 0), (0.5, 0), (1.0, 0.45)], t)
    twitch = math.sin(t * 36) * max(0.0, 1 - abs(t - 1.25) / 0.2) * 0.5
    fk = {
        "root": (0, 90 * roll * 0.55, 0),
        "body": (pitch, 0, 0),
        "neck1": (ease([(0, 0), (0.2, 22), (0.35, 26)], t), 0, 6 * roll),
        "neck2": (ease([(0, 0), (0.2, 18), (0.35, 24)], t), 0, 8 * roll),
        "head": (ease([(0, 0), (0.25, 10), (0.4, -14)], t), 18 * roll, 4 * roll),
        "jaw": (ease([(0, 10), (0.15, 30), (0.6, 24), (1.2, 14)], t) + 6 * twitch, 0, 0),
        "tail1": (-30 + 20 * fold, 0, 8 * roll), "tail2": (-4, 0, 6 * roll), "tail3": (2, 0, 0),
        "ear_L": (-35, 0, 0), "ear_R": (-35, 0, 0),
    }
    for s in ("L", "R"):
        fk["scapula_" + s] = (-14 * fold, 0, 0)
        fk["upperarm_" + s] = (-50 * fold, 0, 0)
        fk["forearm_" + s] = (95 * fold, 0, 0)
        fk["hand_" + s] = (-55 * fold, 0, 0)
        fk["thigh_" + s] = (-62 * fold, 0, 0)
        fk["shin_" + s] = (95 * fold + 10 * twitch, 0, 0)
        fk["foot_" + s] = (-45 * fold, 0, 0)
    return {"fk": fk, "loc": {"root": (0, -0.12 * fold, 0.07 * roll), "body": (0, 0, sink)}, "legs": None}

CLIPS = [
    ("idle", 120, clip_idle, True),
    ("walk", 27, clip_walk, True),
    ("trot", 15, clip_trot, True),
    ("run", 13, clip_run, True),
    ("feed", 90, clip_feed, True),
    ("lunge", 69, clip_lunge, False),
    ("bite", 69, clip_bite, False),
    ("hit", 18, clip_hit, False),
    ("death", 48, death_side(1), False),
    ("death_left", 48, death_side(-1), False),
    ("death_collapse", 45, death_collapse, False),
]
acts = []
for name, n, fn, loop in CLIPS:
    if only and name not in only:
        continue
    acts.append(bake(name, n, fn, loop))
for b in FKB:
    for c in list(pb[b].constraints):
        pb[b].constraints.remove(c)
# Clean rest pose for export.
for b in pb:
    b.matrix_basis = Matrix.Identity(4)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.wm.save_as_mainfile(filepath=out_anims.replace(".glb", ".blend"))
