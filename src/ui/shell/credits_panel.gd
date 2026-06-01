# src/ui/shell/credits_panel.gd
class_name CreditsPanel
extends Control

signal back_pressed

const CREDITS_PATH := "res://src/data/credits.txt"
const SCROLL_DURATION := 15.0

@onready var _back: Button = %Back
@onready var _label: RichTextLabel = $CreditsLabel

func _ready() -> void:
	theme = preload("res://src/ui/theme/game_theme.tres")
	_back.pressed.connect(func() -> void: back_pressed.emit())
	JuicyButton.apply(_back)
	_populate_label()
	_scroll_loop()

func _populate_label() -> void:
	var f := FileAccess.open(CREDITS_PATH, FileAccess.READ)
	if f == null:
		push_error("Could not open %s" % CREDITS_PATH)
		return
	var body := ""
	var current_section := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		if line.begins_with("# "):
			body += "[font_size=48]%s[/font_size]\n\n" % line.substr(2)
		else:
			body += line + "\n"
	f.close()
	_label.text = "[center]" + body + "[/center]"

func _scroll_loop() -> void:
	var viewport_height := get_viewport_rect().size.y
	_label.position.y = viewport_height
	var end_y := -_label.size.y - 100.0
	var tw := create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_label, "position:y", end_y, SCROLL_DURATION)
	tw.tween_callback(_scroll_loop)

func on_foreground_offset(offset: Vector2) -> void:
	position = offset
