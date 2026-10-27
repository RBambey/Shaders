# Glimpse Before Death

![thumbnail](GlimpseBeforeDeath.synScene/thumbnail.png)

**[Open the live preview](https://rbambey.github.io/Shaders/GlimpseBeforeDeath/preview.html)** (runs in the browser; works best in Chrome on a computer with a decent GPU).

The camera flies down a raymarched tunnel that twists and turns at random. The walls cycle through four looks:

- pitted clay
- fuzzy coral
- wet, heartbeat-pulsing flesh
- floral: cobblestones with leafy vines, where the veins become stems lined with flowers

Veins grow, writhe and respawn along the walls. Every so often a wave sweeps down the tunnel and turns them into strings of soap bubbles, which drift off the wall and then melt back into veins. In the floral look the flowers float off instead. An oil-slick thin-film sheen and a slow hue drift cover everything.

## Audio

Only the veins and bubbles (and flowers) react to the music. The walls and the camera ignore it.

| Input | Effect |
|---|---|
| Bass hits | Each hit sends a pulse racing away from the camera down the tunnel. As it passes, the veins and bubbles swell and light up. |
| Highs (`syn_HighLevel`) | Sparkle on the veins and bubbles |

`audio_react` scales all of it. The bass hits are detected in `script.js`. It watches `syn_BassLevel`, keeps the last 4 hits, and passes their age and strength to the shader as `pulse_age0..3` / `pulse_amp0..3`.

## Controls

| Control | What it does |
|---|---|
| `speed` | Forward flight speed |
| `twist` | How hard the tunnel bends (0 = straight) |
| `tunnel_radius` | Tunnel width |
| `vein_density` | Number of veins around the wall |
| `vein_growth_speed` | How fast veins grow, shrink and respawn |
| `bubbles` | How far veins turn into bubbles when the wave passes (0 = never) |
| `bubble_rate` | How often the bubble wave comes around (1 = about every 20 s) |
| `sheen` | Strength of the oil-slick film |
| `hue_drift` | Speed of the palette's hue rotation (0 = fixed colors) |
| `hue_shift` | Manual hue offset |
| `audio_react` | How strongly the music drives the veins and bubbles |

## Performance

The raymarch renders into a 960×540 buffer (`tunnelBuf`, the first pass). The final pass upscales it with a light sharpen. On an M1 Pro at 1080p output this runs at roughly 50–85 fps in Chrome. It drops to about 35–45 fps while the veins are bubbles, and to about 25–30 fps in the floral look. Set `bubbles` to 0 to avoid the bubble cost.

To trade quality for speed, change `WIDTH`/`HEIGHT` under `PASSES` in `scene.json`. For example, 1280×720 is sharper and 640×360 is faster.

## Editing

1. Edit `GlimpseBeforeDeath.synScene/main.glsl`. It is the single source of truth.
2. Run `python3 build_preview.py` to inline the shader and controls into `preview.html`.
3. Refresh `preview.html` in the browser.
4. Copy the `.synScene` folder into Synesthesia.

Preview URL options:

| Option | Effect |
|---|---|
| `?t=38` | Freeze time at 38 s |
| `?speed=2` (any control name) | Override that control |
| `?buf=full` | Render the tunnel at full resolution, to compare |
| `?bench=30` | Time 30 frames and show ms/frame in the tab title |
| `?ui=0` | Hide the panel |

Keys: H toggles the panel, Space pauses.

## Versions

- **Unreleased**: floral look (stones, vines, flowers); veins periodically turn into soap bubbles (`bubbles`, `bubble_rate`); stronger vein contrast.
- **v1.0**: the first release, with the three looks, growing veins, oil-slick sheen, audio reactivity and half-res rendering.
