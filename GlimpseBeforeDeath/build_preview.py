#!/usr/bin/env python3
"""Inline the scene's main.glsl, scene.json controls/passes/images and script.js into preview.html.

main.glsl is the single source of truth: edit it, run this, refresh the browser.
"""
import argparse
import base64
import json
import mimetypes
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("--media", help="image to build in as the media (for a local preview; keep it out of git)")
ap.add_argument("--out", default="preview.html", help="output file, relative to this folder")
args = ap.parse_args()

root = Path(__file__).resolve().parent
scene = root / "GlimpseBeforeDeath.synScene"
glsl = (scene / "main.glsl").read_text()
scene_json = json.loads((scene / "scene.json").read_text())
script_path = scene / "script.js"
script_js = script_path.read_text() if script_path.exists() else ""

html = (root / "preview.template.html").read_text()
html = (html.replace("/*__MAIN_GLSL__*/", glsl)
            .replace("/*__CONTROLS__*/", json.dumps(scene_json["CONTROLS"]))
            .replace("/*__PASSES__*/", json.dumps(scene_json.get("PASSES", [])))
            .replace("/*__SCRIPT_JS__*/", script_js))
images = []
for im in scene_json.get("IMAGES", []):
    path = scene / im["PATH"]
    mime = mimetypes.guess_type(path.name)[0] or "image/png"
    images.append({"NAME": im["NAME"], "DATA": f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode()})
html = html.replace("/*__IMAGES__*/[]", json.dumps(images))
if args.media:
    mime = mimetypes.guess_type(args.media)[0] or "image/jpeg"
    data = base64.b64encode(Path(args.media).read_bytes()).decode()
    html = html.replace("/*__MEDIA__*/null", json.dumps(f"data:{mime};base64,{data}"))

out = root / args.out
out.write_text(html)
print("wrote", out)
