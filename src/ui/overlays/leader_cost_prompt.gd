extends CanvasLayer

signal chosen(by_discard: bool)
signal minimize_requested

@onready var _tickets_btn: Button = $Panel/PayTickets
@onready var _discard_btn: Button = $Panel/PayDiscard

func _ready() -> void:
	_tickets_btn.pressed.connect(func(): _emit(false))
	_discard_btn.pressed.connect(func(): _emit(true))
	$Panel.theme = preload("res://src/ui/theme/game_theme.tres")
	JuicyButton.apply(_tickets_btn)
	JuicyButton.apply(_discard_btn)
	var _min_btn: Button = $Panel/MinimizeButton
	JuicyButton.apply(_min_btn)
	_min_btn.pressed.connect(func(): minimize_requested.emit())

func show_prompt() -> void:
	if not is_node_ready(): await ready
	visible = true
	CardJuice.popup_in($Panel)

func choose_tickets() -> void: _emit(false)
func choose_discard() -> void: _emit(true)

func _emit(by_discard: bool) -> void:
	visible = false
	chosen.emit(by_discard)

func get_animatable_nodes() -> Array[Node]:
	return [$Panel/PromptLabel, _tickets_btn, _discard_btn, $Panel/MinimizeButton]

func get_dim_node() -> Control:
	return $Panel