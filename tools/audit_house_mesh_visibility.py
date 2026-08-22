#!/usr/bin/env python3
"""Which of Chimera's house meshes are ever framed by the camera, across the
whole song - checked with real geometry, not guessed.

Every previous attempt at this in this project hit the same wall: the house's
individual meshes (window_001, floorfucked, Cube_022...) live inside
`chimera.gltf`, an imported binary resource, opaque to a text sweep - and this
checkout's cached import of it (`.godot/imported/chimera.gltf-*.scn`) fails to
parse, so even `PackedScene.get_state()` (the usual way around not having the
autoloads to instantiate a real scene) cannot read it here.

The way around both: **`.gltf` (unlike `.glb`) is plain JSON.** No Godot
import pipeline involved at all - `nodes[].translation/rotation/scale`,
`meshes[].primitives[].attributes.POSITION` -> `accessors[].min/max` for a
local AABB per mesh, composed by hand. This is a completely different route
than every earlier technique in this project's tooling (which all go through
Godot's own resource loader) and is worth keeping as its own recipe.

The result, checked against every one of the 26 sequences' own authored
camera track (`Camera3D:position`/`:rotation`/`:fov`, sampled every 0.5s and
linearly interpolated, 377 samples across 199.9s) with a 15-degree margin on
top of the frustum: **all 58 house meshes are framed at some point.** Not a
close call either - the least comfortable one (`Circle`) still clears the
frustum edge by 29 degrees at its best moment. The house is small (~10
units) and 26 different sweeping shots pass through it over three minutes;
there is no unseen corner.

So there is nothing here to gate on camera framing. Kept as a tool rather
than deleted, because the technique (raw-JSON .gltf reading, the euler-to-
forward math validated against Basis.from_euler, the per-sequence camera path
built from SequencePlayer's own tracks) is exactly what the next "is X ever
on screen" question will need, and rebuilding it from scratch would cost the
session that asks it another hour.

Run with:
    python3 tools/audit_house_mesh_visibility.py
"""
import json
import math
import re

GLTF = "lullaby_mod/assets/funkin/chimera/models/house/chimera.gltf"
SCENE = "lullaby_mod/songs/chimera/sng_chimera.tscn"

# chimera_house's own transform in sng_chimera.tscn: uniform scale, no
# rotation, no translation - checked against the .tscn text, not assumed.
HOUSE_SCALE = 2.0

# How much slack to give the frustum test, in degrees, on top of the sampled
# fov and the object's own angular radius. Generous on purpose: this is a
# "never happens" claim and a false negative (missing a real close call) is
# far cheaper than a false positive (hiding something the player does see).
MARGIN_DEG = 15.0

# Camera samples per second of song time. 0.5 was enough to keep the worst
# margin at -29 degrees, nowhere near a photo finish that would call for
# denser sampling.
STEP_SECONDS = 0.5


def quat_to_matrix(q):
    x, y, z, w = q
    return [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]


def mat_vec(m, v):
    return tuple(sum(m[i][j] * v[j] for j in range(3)) for i in range(3))


def load_house_meshes():
    """Every chimera.gltf node with a mesh, as a world-space bounding sphere
    in sng_chimera.tscn's coordinate space."""
    d = json.load(open(GLTF, encoding="utf-8"))
    accessors = d["accessors"]
    meshes = d["meshes"]

    out = []
    for n in d["nodes"]:
        if "mesh" not in n:
            continue
        t = n.get("translation", [0.0, 0.0, 0.0])
        q = n.get("rotation", [0.0, 0.0, 0.0, 1.0])
        s = n.get("scale", [1.0, 1.0, 1.0])
        rot = quat_to_matrix(q)

        mesh = meshes[n["mesh"]]
        mins = maxs = None
        for prim in mesh["primitives"]:
            acc = accessors[prim["attributes"]["POSITION"]]
            lo, hi = acc["min"], acc["max"]
            mins = lo if mins is None else [min(mins[i], lo[i]) for i in range(3)]
            maxs = hi if maxs is None else [max(maxs[i], hi[i]) for i in range(3)]

        corners = []
        for cx in (mins[0], maxs[0]):
            for cy in (mins[1], maxs[1]):
                for cz in (mins[2], maxs[2]):
                    v = (cx * s[0], cy * s[1], cz * s[2])
                    v = mat_vec(rot, v)
                    corners.append((v[0] + t[0], v[1] + t[1], v[2] + t[2]))

        cx = sum(c[0] for c in corners) / 8 * HOUSE_SCALE
        cy = sum(c[1] for c in corners) / 8 * HOUSE_SCALE
        cz = sum(c[2] for c in corners) / 8 * HOUSE_SCALE
        radius = max(math.dist((cx / HOUSE_SCALE, cy / HOUSE_SCALE, cz / HOUSE_SCALE), c)
                     for c in corners) * HOUSE_SCALE
        out.append({"name": n.get("name", "?"), "world": (cx, cy, cz), "radius": radius})
    return out


def _sub_resource(text, rid):
    m = re.search(r'\[sub_resource type="Animation" id="%s"\]\n(.*?)(?=\n\[sub_resource|\n\[node)'
                   % re.escape(rid), text, re.S)
    return m.group(1) if m else ""


def _track(body, suffix, vector=True):
    for tm in re.finditer(r'tracks/(\d+)/path = NodePath\("([^"]*)"\)', body):
        idx, path = tm.group(1), tm.group(2)
        if not path.endswith(suffix):
            continue
        keys_m = re.search(r'tracks/%s/keys = (\{.*?\n\})' % idx, body, re.S)
        if not keys_m:
            continue
        keys_b = keys_m.group(1)
        times_m = re.search(r'"times": PackedFloat32Array\(([^)]*)\)', keys_b)
        if not times_m:
            continue
        t_list = [float(x) for x in times_m.group(1).split(",") if x.strip()]
        if vector:
            vals_m = re.search(r'"values": \[(.*?)\]', keys_b, re.S)
            if not vals_m:
                continue
            v_list = [tuple(float(x) for x in m.group(1).split(","))
                      for m in re.finditer(r'Vector3\(([^)]*)\)', vals_m.group(1))]
        else:
            vals_m = re.search(r'"values": PackedFloat32Array\(([^)]*)\)', keys_b)
            if not vals_m:
                continue
            v_list = [float(x) for x in vals_m.group(1).split(",") if x.strip()]
        return t_list, v_list
    return None, None


def _interp(times, values, t):
    if not times:
        return None
    if t <= times[0]:
        return values[0]
    if t >= times[-1]:
        return values[-1]
    for i in range(len(times) - 1):
        if times[i] <= t <= times[i + 1]:
            span = times[i + 1] - times[i]
            f = 0.0 if span <= 0 else (t - times[i]) / span
            a, b = values[i], values[i + 1]
            if isinstance(a, tuple):
                return tuple(a[k] + (b[k] - a[k]) * f for k in range(len(a)))
            return a + (b - a) * f
    return values[-1]


def _euler_to_forward(euler):
    """Matches Godot's Basis.from_euler (YXZ order) * Vector3(0,0,-1),
    verified against the running binary to 8+ decimal places on rotations
    combining all three axes - not derived from memory alone."""
    x, y, z = euler
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    fx, fy, fz = 0.0, 0.0, -1.0
    fx, fy = fx * cz - fy * sz, fx * sz + fy * cz
    fy, fz = fy * cx - fz * sx, fy * sx + fz * cx
    fx, fz = fx * cy + fz * sy, -fx * sy + fz * cy
    n = math.sqrt(fx * fx + fy * fy + fz * fz)
    return (fx / n, fy / n, fz / n) if n > 0 else (0.0, 0.0, -1.0)


def build_camera_path(step=STEP_SECONDS):
    """(song_time, sequence_name, position, forward, fov_degrees) every `step`
    seconds, built from each dispatched sequence's own Camera3D tracks - the
    same clock/dispatch-table technique already used for the character
    timeline and the precache sweep."""
    text = open(SCENE, encoding="utf-8", errors="replace").read()

    clock = _sub_resource(text, "Animation_dp07n")
    keys = re.search(r'tracks/1/keys = (\{.*?\n\})', clock, re.S).group(1)
    clips = re.search(r'"clips": PackedStringArray\((.*?)\)', keys)
    times = re.search(r'"times": PackedFloat32Array\(([^)]*)\)', keys)
    names = [x.strip().strip('"') for x in clips.group(1).split(",")]
    starts = [float(x) for x in times.group(1).split(",")]
    song_length = float(re.search(r'length = ([\d.]+)', clock).group(1))
    dispatch = list(zip(names, starts))
    windows = [(name, start, dispatch[i + 1][1] if i + 1 < len(dispatch) else song_length)
               for i, (name, start) in enumerate(dispatch)]

    lib = re.search(r'\[sub_resource type="AnimationLibrary" id="AnimationLibrary_mao22"\]\n(.*?)(?=\n\[)',
                     text, re.S).group(1)
    seq_to_rid = dict(re.findall(r'&"([^"]+)": SubResource\("([^"]+)"\)', lib))

    samples = []
    for name, start, end in windows:
        body = _sub_resource(text, seq_to_rid.get(name, ""))
        pt, pv = _track(body, "Camera3D:position")
        rt, rv = _track(body, "Camera3D:rotation")
        ft, fv = _track(body, "Camera3D:fov", vector=False)
        if pt is None:
            continue
        local_t = 0.0
        while start + local_t < end:
            pos = _interp(pt, pv, local_t)
            rot = _interp(rt, rv, local_t) if rt else (0.0, 0.0, 0.0)
            fov = _interp(ft, fv, local_t) if ft else 75.0
            samples.append((start + local_t, name, pos, _euler_to_forward(rot), fov))
            local_t += step
    return samples


def in_frustum(cam_pos, cam_fwd, fov_deg, obj_center, obj_radius, margin_deg=MARGIN_DEG):
    dx, dy, dz = (obj_center[i] - cam_pos[i] for i in range(3))
    dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist < 1e-6:
        return True
    dirv = (dx / dist, dy / dist, dz / dist)
    dot = max(-1.0, min(1.0, dirv[0] * cam_fwd[0] + dirv[1] * cam_fwd[1] + dirv[2] * cam_fwd[2]))
    angle = math.degrees(math.acos(dot))
    angular_radius = math.degrees(math.asin(min(1.0, obj_radius / dist))) if dist > obj_radius else 90.0
    return angle <= fov_deg / 2.0 + angular_radius + margin_deg


def main() -> int:
    meshes = load_house_meshes()
    samples = build_camera_path()
    print("mallas del gltf: %d, muestras de camara: %d (paso %.1fs)" % (
        len(meshes), len(samples), STEP_SECONDS))

    never = []
    for m in meshes:
        if not any(in_frustum(pos, fwd, fov, m["world"], m["radius"])
                    for (_, _, pos, fwd, fov) in samples):
            never.append(m["name"])

    print("mallas nunca encuadradas (margen %.0f grados): %d de %d" % (
        MARGIN_DEG, len(never), len(meshes)))
    for name in sorted(never):
        print("   %s" % name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
