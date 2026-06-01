# src/ui/shell/credits_panel.gd
class_name CreditsPanel
extends Control

signal back_pressed

@onready var _back: Button = %Back

func _ready() -> void:
	theme = preload("res://src/ui/theme/game_theme.tres")
	_back.pressed.connect(func() -> void: back_pressed.emit())
	JuicyButton.apply(_back)
