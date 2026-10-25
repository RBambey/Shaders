#!/usr/bin/env python3
"""Inline GlimpseBeforeDeath.synScene/main.glsl + scene.json controls into preview.html.

main.glsl is the single source of truth: edit it, run this, refresh the browser.
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parent
scene = root / "GlimpseBeforeDeath.synScene"
glsl = (scene / "main.glsl").read_text()
scene_json = json.loads((scene / "scene.json").read_text())

html = (root / "preview.template.html").read_text()
html = (html.replace("/*__MAIN_GLSL__*/", glsl)
            .replace("/*__CONTROLS__*/", json.dumps(scene_json["CONTROLS"]))
            .replace("/*__PASSES__*/", json.dumps(scene_json.get("PASSES", []))))
(root / "preview.html").write_text(html)
print("wrote", root / "preview.html")
