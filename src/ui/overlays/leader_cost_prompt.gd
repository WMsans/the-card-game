extends CanvasLayer

signal chosen(by_discard: bool)

@onready var _tickets_btn: Button = $Panel/PayTickets
@onready var _discard_btn: Button = $Panel/PayDiscard

func _ready() -> void:
	_tickets_btn.pressed.connect(func(): _emit(false))
	_discard_btn.pressed.connect(func(): _emit(true))

func show_prompt() -> void:
	if not is_node_ready(): await ready
	visible = true

func choose_tickets() -> void: _emit(false)
func choose_discard() -> void: _emit(true)

func _emit(by_discard: bool) -> void:
	visible = false
	chosen.emit(by_discard)