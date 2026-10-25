# Shaders

GLSL scenes for [Synesthesia](https://synesthesia.live), each with a standalone HTML preview.

| Scene | Description |
|---|---|
| [Glimpse Before Death](GlimpseBeforeDeath/) | Flying down a twisting organic tunnel that cycles through clay, coral and flesh under an oil-slick sheen, with growing veins. Audio-reactive. |

## Layout

Each scene lives in its own folder:

- `<Name>.synScene/`: the Synesthesia scene (`main.glsl`, `scene.json`, `thumbnail.png`). Copy this folder into Synesthesia to use it.
- `preview.html`: open it in a browser to run the shader without Synesthesia. Sliders fake the scene controls and the audio.
- `preview.template.html` + `build_preview.py`: rebuild `preview.html` after editing `main.glsl`.
