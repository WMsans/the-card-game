# src/ui/shell/settings_panel.gd
class_name SettingsPanel
extends Control

signal back_pressed

var _settings: GameSettings

@onready var _fullscreen: CheckButton = %Fullscreen
@onready var _vsync: CheckButton = %Vsync
@onready var _back: Button = %Back

func _ready() -> void:
	theme = preload("res://src/ui/theme/game_theme.tres")
	_back.pressed.connect(func() -> void: back_pressed.emit())
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_vsync.toggled.connect(_on_vsync_toggled)
	JuicyButton.apply(_back)
	if _settings != null:
		_refresh()

# Binds the live settings object the panel reads from and writes to.
func bind(settings: GameSettings) -> void:
	_settings = settings
	if is_node_ready():
		_refresh()

func _refresh() -> void:
	_fullscreen.button_pressed = _settings.fullscreen
	_vsync.button_pressed = _settings.vsync

func _on_fullscreen_toggled(on: bool) -> void:
	if _settings == null: return
	_settings.fullscreen = on
	_settings.apply()
	_settings.save()

func on_foreground_offset(offset: Vector2) -> void:
	position = offset

func _on_vsync_toggled(on: bool) -> void:
	if _settings == null: return
	_settings.vsync = on
	_settings.apply()
	_settings.save()
