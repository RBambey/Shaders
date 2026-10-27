"""Bake Blender's 'Head (Sculpting) - Realistic' into a radius map for the shader's mannequin heads.

Run (on the Human Base Meshes bundle, CC0, from Blender Studio):
  /Applications/Blender.app/Contents/MacOS/Blender -b human_base_meshes_bundle.blend \
      --python bake_head.py -- --out ../GlimpseBeforeDeath.synScene/images/head_radius.png

For each direction from a point inside the cranium, rays find the outermost head surface
(eyeballs included, so the eyes read as closed mannequin eyes; the mouth cavity is skipped).
Sideways it keeps the skull and drops the ears; down the neck a flat floor below the chin
closes the head off. A light blur softens any steep spots for the raymarcher. The distance is stored in an
equirectangular PNG that the shader reads to get the head's shape:
  u = azimuth around the up axis (0.5 = straight ahead), v = 1 at the crown, 0 underneath.
  distance / RMAX is packed into 16 bits: value = (R * 255 + G) / 255.
Head frame, matching the shader: x across, y up, z = the way the face looks;
units: 1 = half the crown-to-chin height.
Prints the eye positions in that frame, used to line the face media up with the eyes.
"""
import math
import struct
import sys
import zlib

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[argv.index("--out") + 1] if "--out" in argv else "head_radius.png"
W, H = 512, 256
RMAX = 1.6           # largest storable distance (in head units); the neck runs past it and is clipped

HEAD = "GEO-head_sculpting_realistic"
EYES = ["GEO-head_sculpting_realistic.sclera.L", "GEO-head_sculpting_realistic.sclera.R"]

depsgraph = bpy.context.evaluated_depsgraph_get()


def world_mesh(name):
    ob = bpy.data.objects[name]
    ev = ob.evaluated_get(depsgraph)
    me = ev.to_mesh()
    verts = [ev.matrix_world @ v.co for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    ev.to_mesh_clear()
    return verts, polys


verts, polys = [], []
for name in [HEAD] + EYES:
    v, p = world_mesh(name)
    off = len(verts)
    verts += v
    polys += [tuple(i + off for i in poly) for poly in p]
bvh = BVHTree.FromPolygons(verts, polys)

# ---- head frame: centre inside the cranium, scale = half the crown-to-chin height
head_v, _ = world_mesh(HEAD)
eye_c = [sum((v for v in world_mesh(n)[0]), Vector()) / len(world_mesh(n)[0]) for n in EYES]
eye_mid = (eye_c[0] + eye_c[1]) / 2
zs = [v.z for v in head_v]
crown = max(zs)
# chin: lowest point of the face in front of the neck (the neck runs on further down)
front_y = min(v.y for v in head_v)
face_verts = [v for v in head_v if v.y < front_y + 0.06 and abs(v.x - eye_mid.x) < 0.03]
chin = min(v.z for v in face_verts)
scale = (crown - chin) / 2
ys = [v.y for v in head_v if v.z > eye_mid.z - 0.02]
centre = Vector((eye_mid.x, (min(ys) + max(ys)) / 2, (crown + chin) / 2))
# face direction: from the centre towards the eyes, flattened
fwd = Vector((eye_mid.x - centre.x, eye_mid.y - centre.y, 0)).normalized()
up = Vector((0, 0, 1))
right = up.cross(fwd).normalized()      # x axis such that (x, y=up, z=fwd) is right-handed


def to_head(p):
    d = p - centre
    return Vector((d.dot(right), d.dot(up), d.dot(fwd))) / scale


print(f"centre={tuple(round(c, 4) for c in centre)} scale={scale:.4f} fwd={tuple(round(c, 3) for c in fwd)}")
for n, c in zip(EYES, eye_c):
    print("eye", n.rsplit(".", 1)[-1], tuple(round(c, 3) for c in to_head(c)))

# ---- cast rays
img = np.zeros((H, W), dtype=np.float32)
for j in range(H):                       # j = 0 is the bottom row (underneath)
    theta = (1.0 - (j + 0.5) / H) * math.pi
    for i in range(W):
        phi = ((i + 0.5) / W - 0.5) * 2.0 * math.pi
        q = Vector((math.sin(theta) * math.sin(phi), math.cos(theta), math.sin(theta) * math.cos(phi)))
        d = (right * q.x + up * q.y + fwd * q.z).normalized()
        # first and outermost surfaces along the ray (from in here the eyeball backs and the
        # mouth cavity come first, so the face needs the outermost one)
        first = far = None
        origin = centre
        for _ in range(16):
            hit, _, _, dist = bvh.ray_cast(origin, d)
            if hit is None:
                break
            far = (hit - centre).length
            first = far if first is None else first
            origin = hit + d * 1e-5
        if far is not None:
            # sideways the first hit is the skull, which drops the ears (steep, and not very mannequin)
            side = min(max((abs(q.x) - 0.55) / 0.2, 0.0), 1.0)
            far = far + (first - far) * side
        # directions down the neck: a flat floor below the chin closes the head off (the shader's
        # own neck takes over); min() keeps the jaw-to-floor edge continuous
        floor = (1.2 * scale) / -q.y if q.y < -1e-3 else RMAX * scale
        far = min(far if far is not None else RMAX * scale, floor, RMAX * scale)
        img[j, i] = far
# light blur (wrapping around the azimuth) to take the edge off any remaining steep spots
k = np.array([1, 4, 6, 4, 1], dtype=np.float32) / 16.0
img = sum(w * np.roll(img, o, axis=1) for w, o in zip(k, range(-2, 3)))
pad = np.pad(img, ((2, 2), (0, 0)), mode="edge")
img = sum(w * pad[2 + o:2 + o + H] for w, o in zip(k, range(-2, 3)))
r = np.clip(img / scale / RMAX, 0.0, 1.0)
print(f"radius range {img.min() / scale:.3f}..{img.max() / scale:.3f} head units")

# ---- pack into 16 bits over R + G and write a plain PNG (no colour metadata)
v = r * 255.0
hi = np.floor(v)
lo = np.round((v - hi) * 255.0)
rgba = np.zeros((H, W, 4), dtype=np.uint8)
rgba[..., 0] = hi.astype(np.uint8)
rgba[..., 1] = lo.astype(np.uint8)
rgba[..., 3] = 255
rows = rgba[::-1]                        # PNG stores the top row first
raw = b"".join(b"\x00" + row.tobytes() for row in rows)


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)) \
      + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
with open(bpy.path.abspath(OUT), "wb") as f:
    f.write(png)
print("wrote", OUT)
