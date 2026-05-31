extends CanvasLayer

signal expand_pressed

@onready var _tab: HBoxContainer = $Tab
@onready var _title: Label = $Tab/Title
@onready var _expand_btn: Button = $Tab/ExpandButton

func _ready() -> void:
	_tab.scale = Vector2.ZERO
	_tab.visible = false
	_expand_btn.pressed.connect(_on_expand_pressed)
	JuicyButton.apply(_expand_btn)

func _on_expand_pressed() -> void:
	expand_pressed.emit()

func show_bar(title_text: String) -> void:
	_title.text = title_text
	visible = true
	_tab.visible = true
	var tw := _tab.create_tween()
	_tab.scale = Vector2.ZERO
	tw.tween_property(_tab, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func hide_bar() -> void:
	var tw := _tab.create_tween()
	tw.tween_property(_tab, "scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_tab.visible = false
		visible = false
	)
