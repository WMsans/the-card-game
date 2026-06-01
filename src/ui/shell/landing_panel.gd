# src/ui/shell/landing_panel.gd
class_name LandingPanel
extends Control

signal play_pressed
signal compendium_pressed
signal settings_pressed
signal quit_pressed
signal credits_pressed

const DRIFT_COUNT := 5
const CARD_BACK := preload("res://src/ui/assets/frames/back.png")

@onready var _drift: Node2D = $DriftingCards

func _ready() -> void:
	theme = preload("res://src/ui/theme/game_theme.tres")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Play.pressed.connect(func() -> void: play_pressed.emit())
	%Compendium.pressed.connect(func() -> void: compendium_pressed.emit())
	%Settings.pressed.connect(func() -> void: settings_pressed.emit())
	%Quit.pressed.connect(func() -> void: quit_pressed.emit())
	%Credits.pressed.connect(func() -> void: credits_pressed.emit())
	for b in [%Play, %Compendium, %Settings, %Quit, %Credits]:
		JuicyButton.apply(b)
	_spawn_drifting_cards()

func _spawn_drifting_cards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260531
	for i in range(DRIFT_COUNT):
		var s := Sprite2D.new()
		s.texture = CARD_BACK
		s.scale = Vector2.ONE * rng.randf_range(0.5, 0.9)
		var base := Vector2(rng.randf_range(1000, 1750), rng.randf_range(150, 800))
		s.position = base
		s.rotation = rng.randf_range(-0.3, 0.3)
		_drift.add_child(s)
		var t := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var dy := rng.randf_range(20, 60)
		t.tween_property(s, "position:y", base.y + dy, rng.randf_range(3.0, 6.0))
		t.tween_property(s, "position:y", base.y, rng.randf_range(3.0, 6.0))

func on_foreground_offset(offset: Vector2) -> void:
	position = offset
