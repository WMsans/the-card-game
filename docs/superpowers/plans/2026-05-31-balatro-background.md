# Balatro-Style Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an animated, two-layer parallax noise background to Match, inspired by Balatro's iconic wallpaper.

**Architecture:** A standalone `BalatroBg` scene (ColorRect + shader + script) generates domain-warped noise mapped to UiPalette's plum/purple colors, drifts it over time, and computes mouse-tracking offsets for two-layer parallax (background shifts slightly, foreground shifts more). The scene is instanced into Match, replacing the current FeltFrame panel.

**Tech Stack:** Godot 4 GDScript, canvas_item shader, NoiseTexture2D/FastNoiseLite

---

### Task 1: Create the background_noise.gdshader

**Files:**
- Create: `src/ui/assets/shaders/background_noise.gdshader`

- [ ] **Step 1: Write the shader file**

```gdshader
shader_type canvas_item;

uniform sampler2D noise_texture;
uniform sampler2D warp_texture;
uniform float drift_speed : hint_range(0.0, 0.1) = 0.02;
uniform float drift_angle : hint_range(0.0, 6.283) = 0.785;
uniform float noise_scale : hint_range(0.1, 10.0) = 1.0;
uniform float warp_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec4 color_dark : source_color = vec4(0.17, 0.13, 0.20, 1.0);
uniform vec4 color_bright : source_color = vec4(0.23, 0.18, 0.28, 1.0);

void fragment() {
    vec2 drift_dir = vec2(cos(drift_angle), sin(drift_angle));
    float drift_offset = drift_speed * TIME;

    // Sample warp texture at offset UVs for independent X/Y distortion
    float warp_x = texture(warp_texture, (UV + vec2(0.0, 0.37)) * noise_scale + drift_dir * drift_offset * 0.7).r - 0.5;
    float warp_y = texture(warp_texture, (UV + vec2(0.37, 0.0)) * noise_scale + drift_dir * drift_offset * 0.7).r - 0.5;
    vec2 warp_offset = vec2(warp_x, warp_y) * warp_strength;

    // Sample base noise with drift + warp
    float noise_val = texture(noise_texture, UV * noise_scale + drift_dir * drift_offset + warp_offset).r;

    vec3 color = mix(color_dark.rgb, color_bright.rgb, noise_val);
    COLOR = vec4(color, 1.0);
}
```

- [ ] **Step 2: Commit**

```bash
git add src/ui/assets/shaders/background_noise.gdshader
git commit -m "feat: add background noise shader for Balatro-style wallpaper"
```

---

### Task 2: Create the balatro_bg.gd script

**Files:**
- Create: `src/ui/match/balatro_bg.gd`

- [ ] **Step 1: Write the script**

Key design decision: both bg and fg offsets track their own smoothed state independently (`_bg_current` and `_fg_current`), avoiding a bug where sharing `position` for both would cause inconsistent frame-to-frame updates.

```gdscript
class_name BalatroBg
extends ColorRect

signal foreground_offset(offset: Vector2)

@export var bg_max_offset: Vector2 = Vector2(4, 3)
@export var fg_max_offset: Vector2 = Vector2(12, 10)
@export var smoothing: float = 2.0

var _bg_current: Vector2 = Vector2.ZERO
var _fg_current: Vector2 = Vector2.ZERO

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    color = UiPalette.BG
    _setup_material()

func _setup_material() -> void:
    var base_noise := FastNoiseLite.new()
    base_noise.frequency = 0.003
    base_noise.fractal_octaves = 1
    base_noise.fractal_gain = 0.075
    base_noise.domain_warp_enabled = true
    base_noise.domain_warp_amplitude = 0.05

    var warp_noise := FastNoiseLite.new()
    warp_noise.seed = 42
    warp_noise.frequency = 0.004
    warp_noise.fractal_octaves = 1
    warp_noise.fractal_gain = 0.075

    var base_tex := NoiseTexture2D.new()
    base_tex.width = 1920
    base_tex.height = 1080
    base_tex.seamless = false
    base_tex.noise = base_noise

    var warp_tex := NoiseTexture2D.new()
    warp_tex.width = 1920
    warp_tex.height = 1080
    warp_tex.seamless = false
    warp_tex.noise = warp_noise

    var mat := ShaderMaterial.new()
    mat.shader = preload("res://src/ui/assets/shaders/background_noise.gdshader")
    mat.set_shader_parameter("noise_texture", base_tex)
    mat.set_shader_parameter("warp_texture", warp_tex)
    mat.set_shader_parameter("drift_speed", 0.02)
    mat.set_shader_parameter("drift_angle", 0.785)
    mat.set_shader_parameter("noise_scale", 1.0)
    mat.set_shader_parameter("warp_strength", 0.3)
    mat.set_shader_parameter("color_dark", UiPalette.BG)
    mat.set_shader_parameter("color_bright", UiPalette.PANEL)
    material = mat

func _process(delta: float) -> void:
    var center := get_viewport_rect().size / 2.0
    var dist := get_global_mouse_position() - center
    var normalized := dist / center

    var bg_target := Vector2(-bg_max_offset.x * normalized.x, -bg_max_offset.y * normalized.y)
    var fg_target := Vector2(-fg_max_offset.x * normalized.x, -fg_max_offset.y * normalized.y)

    _bg_current = _bg_current.lerp(bg_target, smoothing * delta)
    _fg_current = _fg_current.lerp(fg_target, smoothing * delta)

    position = _bg_current
    foreground_offset.emit(_fg_current)
```

- [ ] **Step 2: Commit**

```bash
git add src/ui/match/balatro_bg.gd
git commit -m "feat: add BalatroBg script with two-layer parallax"
```

---

### Task 3: Create the balatro_bg.tscn scene

**Files:**
- Create: `src/ui/match/balatro_bg.tscn`

- [ ] **Step 1: Write the scene file**

The scene is a minimal ColorRect with the BalatroBg script. All material and texture setup is done programmatically in `_ready()`.

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/match/balatro_bg.gd" id="1_script"]

[node name="BalatroBg" type="ColorRect"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
color = Color(0.17, 0.13, 0.2, 1)
script = ExtResource("1_script")
```

Notes:
- `anchors_preset = 15` = full rect (fills parent)
- `mouse_filter = 2` = MOUSE_FILTER_IGNORE (clicks pass through)
- `color = Color(0.17, 0.13, 0.2, 1)` matches UiPalette.BG as fallback before shader loads
- The script's `_ready()` sets up the ShaderMaterial and overrides this color

- [ ] **Step 2: Commit**

```bash
git add src/ui/match/balatro_bg.tscn
git commit -m "feat: add BalatroBg scene file"
```

---

### Task 4: Integrate BalatroBg into Match

**Files:**
- Modify: `src/ui/match/match.gd` — add bg reference, connect signal, handle offset
- Modify: `src/ui/match/match.tscn` — instance BalatroBg, remove FeltFrame

- [ ] **Step 1: Add BalatroBg reference and signal handler to match.gd**

Add these lines to `src/ui/match/match.gd`:

After the existing `@onready` declarations (around line 30), add:

```gdscript
@onready var _bg: BalatroBg = $BalatroBg
```

In the `_ready()` function, after the existing `theme = THEME` line and before `JuicyButton.apply(_end_turn)`, add:

```gdscript
_bg.foreground_offset.connect(_on_foreground_offset)
```

Add a new handler function at the end of the class (before the final closing, or after `_overlay_title`):

```gdscript
func _on_foreground_offset(offset: Vector2) -> void:
    $Table.position = offset
```

- [ ] **Step 2: Update match.tscn — add BalatroBg instance, remove FeltFrame**

In `src/ui/match/match.tscn`:

**a) Add ext_resource for BalatroBg scene** — add this line after the existing ext_resource lines:

```
[ext_resource type="PackedScene" path="res://src/ui/match/balatro_bg.tscn" id="21_bg"]
```

**b) Add BalatroBg node** — after the `[node name="Match" ...]` section and BEFORE the `[node name="Table" ...]` section, add:

```
[node name="BalatroBg" parent="." instance=ExtResource("21_bg")]
```

This places BalatroBg as the first child of Match, before Table, so it renders behind everything.

**c) Remove FeltFrame node** — delete these lines entirely:

```
[node name="FeltFrame" type="Panel" parent="Table" unique_id=512000001]
layout_mode = 0
offset_left = 300.0
offset_top = 220.0
offset_right = 1620.0
offset_bottom = 800.0
mouse_filter = 2
theme = ExtResource("14_theme")
```

**d) Update load_steps** — increase the `load_steps` count in the first line of the .tscn by 1 (adding one new ext_resource).

- [ ] **Step 3: Import the project to generate UIDs**

```bash
godot --headless --path /Users/jeremyzhao/Development/godot/the-card-game --import
```

This generates .uid files for the new shader and scene, and validates the .tscn format.

- [ ] **Step 4: Commit**

```bash
git add src/ui/match/match.gd src/ui/match/match.tscn
git commit -m "feat: integrate BalatroBg into Match, remove FeltFrame"
```

---

### Task 5: Visual verification

- [ ] **Step 1: Run the project in the Godot editor or via command line**

Open the project in the Godot editor and run the Match scene (or start from MainMenu and click Play). Verify:

1. The background shows a dark plum/purple noise pattern (not solid color)
2. The noise pattern drifts slowly over time (subtle animation)
3. Moving the mouse causes the foreground (Table contents) to shift opposite to the mouse direction
4. The background shifts slightly in the same direction as the foreground, but less (two-layer depth)
5. The old FeltFrame panel is gone
6. No visual glitches, missing textures, or shader errors in the console
7. All game interactions still work (card drag, attack targeting, end turn, etc.)

- [ ] **Step 2: Adjust parameters if needed**

If the noise is too subtle/too loud, adjust in `balatro_bg.gd` `_setup_material()`:
- Increase `warp_strength` (default 0.3) for more visible warping
- Change `drift_speed` (default 0.02) for faster/slower animation
- Change `bg_max_offset` / `fg_max_offset` for parallax intensity
- Change `smoothing` (default 2.0) for faster/slower response