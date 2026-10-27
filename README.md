# Shaders

GLSL scenes for [Synesthesia](https://synesthesia.live), each with a standalone HTML preview.

| Scene | Description |
|---|---|
| [Glimpse Before Death](GlimpseBeforeDeath/) ([live preview](https://rbambey.github.io/Shaders/GlimpseBeforeDeath/preview.html)) | Flying down a twisting organic tunnel that cycles through clay, coral, flesh and flowers under an oil-slick sheen, with growing veins. The veins and bubbles react to the music. |

## Layout

Each scene lives in its own folder:

- `<Name>.synScene/`: the Synesthesia scene (`main.glsl`, `scene.json`, `thumbnail.png`, and `script.js` if it has one). Copy this folder into Synesthesia to use it.
- `preview.html`: open it in a browser to run the shader without Synesthesia. Sliders fake the scene controls and the audio.
- `preview.template.html` + `build_preview.py`: rebuild `preview.html` after editing `main.glsl`.
