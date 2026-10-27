#!/usr/bin/env python3
"""Inline the scene's main.glsl, scene.json controls/passes and script.js into preview.html.

main.glsl is the single source of truth: edit it, run this, refresh the browser.
"""
import json
from pathlib import Path

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
(root / "preview.html").write_text(html)
print("wrote", root / "preview.html")
