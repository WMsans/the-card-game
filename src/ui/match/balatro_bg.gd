class_name BalatroBg
extends ColorRect

signal foreground_offset(offset: Vector2)

@export var bg_max_offset: Vector2 = Vector2(4, 3)
@export var fg_max_offset: Vector2 = Vector2(12, 10)
@export var smoothing: float = 2.0
@export var trauma_decay: float = 1.5
@export var shake_max: Vector2 = Vector2(40, 30)

var _trauma: float = 0.0
var _bg_current: Vector2 = Vector2.ZERO
var _fg_current: Vector2 = Vector2.ZERO
var _parallax_padding: Vector2

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func get_trauma() -> float:
	return _trauma

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = UiPalette.BG
	_setup_material()
	_parallax_padding = bg_max_offset + Vector2(4, 4)

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

	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	var shake := _trauma * _trauma
	var jolt := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
	var bg_jolt := jolt * shake_max * (bg_max_offset / fg_max_offset)
	var fg_jolt := jolt * shake_max

	offset_left = -_parallax_padding.x + _bg_current.x + bg_jolt.x
	offset_top = -_parallax_padding.y + _bg_current.y + bg_jolt.y
	offset_right = _parallax_padding.x + _bg_current.x + bg_jolt.x
	offset_bottom = _parallax_padding.y + _bg_current.y + bg_jolt.y
	foreground_offset.emit(_fg_current + fg_jolt)
