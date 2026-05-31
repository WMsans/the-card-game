# Balatro-Style Background

## Overview

Add an animated, two-layer parallax background inspired by Balatro's iconic wallpaper. The background uses domain-warped fractal noise mapped to the project's existing plum/purple palette, with slow animated drift and mouse-tracking parallax on both the background and foreground layers.

## Approach

**Standalone Background Scene (Approach 2).** Create a self-contained `balatro_bg.tscn` packed scene with its own shader and script. Instance it into Match and optionally MainMenu. Clean separation, reusable, `@export`-tunable.

## Components

### 1. Shader — `background_noise.gdshader`

A `canvas_item` shader applied to a full-screen `ColorRect`.

**Noise generation:**
- Two `FastNoiseLite` resources created as sub-resources in the scene:
  - **Base noise:** `frequency = 0.003`, `fractal_octaves = 1`, `fractal_gain = 0.075`, domain warping enabled with low amplitude for organic cloud-like patterns
  - **Warp noise:** similar settings but different seed, used to distort the base noise UVs for additional organic movement
- Both assigned as shader uniform textures (`noise_texture`, `warp_texture`)

**Shader logic:**
- Sample `warp_texture` at `UV + TIME * drift_speed * drift_direction` to compute a UV distortion offset
- Sample `noise_texture` at `(UV + warp_offset) + TIME * drift_speed * drift_direction` for the base pattern
- Map the noise value through a two-color gradient: `color_dark` (UiPalette.BG, ~2B2133) to `color_bright` (UiPalette.PANEL, ~3B2E47)
- This keeps the noise in the same purple family as the current flat backgrounds

**Uniforms:**
| Uniform | Type | Default | Purpose |
|---|---|---|---|
| `noise_texture` | sampler2D | (base FastNoiseLite) | Base noise pattern |
| `warp_texture` | sampler2D | (warp FastNoiseLite) | UV distortion source |
| `drift_speed` | float | 0.02 | How fast the noise drifts over time |
| `drift_angle` | float | 0.785 | Direction of drift in radians (~45 degrees) |
| `noise_scale` | float | 1.0 | Overall scale multiplier for UV |
| `warp_strength` | float | 0.3 | How strongly warp_texture distorts UVs |
| `color_dark` | Color | (0.17, 0.13, 0.20, 1.0) | Gradient dark end — matches UiPalette.BG |
| `color_bright` | Color | (0.23, 0.18, 0.28, 1.0) | Gradient bright end — matches UiPalette.PANEL |

### 2. Background Scene — `balatro_bg.tscn` + `balatro_bg.gd`

**Scene tree:**
```
BalatroBg (ColorRect, full-rect anchors)
  └ ShaderMaterial with background_noise.gdshader
```

Two `FastNoiseLite` sub-resources with `NoiseTexture2D` wrappers are assigned to the shader uniforms.

**Script (`balatro_bg.gd`):**
- Extends `ColorRect`
- Tracks mouse position relative to viewport center each frame
- **Two-layer parallax:**
  - Shifts own position (background layer) by `bg_max_offset` pixels — slow drift
  - Emits `foreground_offset` signal each frame with `fg_max_offset` pixels — faster drift for foreground
  - Both use smoothed interpolation: `lerp(current, target, smoothing * delta)`
- `@export` configuration:
  - `bg_max_offset: Vector2 = Vector2(4, 3)` — background parallax range (subtle)
  - `fg_max_offset: Vector2 = Vector2(12, 10)` — foreground parallax range (Balatro-matching)
  - `smoothing: float = 2.0` — interpolation speed
- `signal foreground_offset(offset: Vector2)` — emitted every frame

### 3. Integration into Match

- Instance `balatro_bg.tscn` as the first child of `Match` in `match.tscn` (behind `Table`)
- In `match.gd`, connect to `BalatroBg.foreground_offset` signal and apply the offset to `Table.position`
- Remove or repurpose the current `FeltFrame` Panel — its area is covered by the noise background
- Optionally instance `balatro_bg.tscn` in `main_menu.tscn` for visual consistency across scenes

### 4. File Locations

| File | Path |
|---|---|
| Shader | `src/ui/assets/shaders/background_noise.gdshader` |
| Script | `src/ui/match/balatro_bg.gd` |
| Scene | `src/ui/match/balatro_bg.tscn` |

Script and scene live alongside the Match scene since they're match-specific UI, following existing project structure. The shader lives with other shaders in `src/ui/assets/shaders/`.

### 5. Testing

- Visual verification: background renders at 1920x1080 with correct plum/purple gradient mapping
- Parallax verification: mouse movement produces smooth two-layer depth shift
- `@export` defaults produce balanced visuals (noise not too bright/dark, drift not too fast/slow)
- No unit tests — this is visual polish verified by inspection

## Out of Scope

- VHS/CRT post-processing layer (not selected in design)
- Color grading / WorldEnvironment changes (not selected in design)
- Dynamic color palette changes (e.g., per-deck themes) — could be a future enhancement
- MainMenu integration is optional; primary target is Match scene