extends CanvasLayer

signal expand_pressed

const THEME := preload("res://src/ui/theme/game_theme.tres")

@onready var _tab: HBoxContainer = $Tab
@onready var _title: Label = $Tab/Title
@onready var _expand_btn: Button = $Tab/ExpandButton

var _tween: Tween

func _ready() -> void:
	_tab.scale = Vector2.ZERO
	_tab.visible = false
	_tab.theme = THEME
	_expand_btn.pressed.connect(_on_expand_pressed)
	JuicyButton.apply(_expand_btn)

func _on_expand_pressed() -> void:
	expand_pressed.emit()

func show_bar(title_text: String) -> void:
	if not is_node_ready():
		await ready
	_title.text = title_text
	visible = true
	_tab.visible = true
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = _tab.create_tween()
	_tab.scale = Vector2.ZERO
	_tween.tween_property(_tab, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func hide_bar() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = _tab.create_tween()
	_tween.tween_property(_tab, "scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func():
		_tab.visible = false
		visible = false
	)
