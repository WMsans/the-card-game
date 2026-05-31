# src/ui/overlays/trap_reveal_overlay.gd
extends CanvasLayer

signal picked(option: int)

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

@onready var _slot: Control = $Panel/CardSlot
@onready var _name: Label = $Panel/TrapName
@onready var _context: Label = $Panel/Context
@onready var _buttons: HBoxContainer = $Panel/Buttons

func _ready() -> void:
	$Panel.theme = preload("res://src/ui/theme/game_theme.tres")

func show_reveal(trap: CardInstance, context: String, options: Array, interactive: bool) -> void:
	if not is_node_ready(): await ready
	for c in _slot.get_children(): c.queue_free()
	var cv: CardView = CARD_VIEW.instantiate()
	cv.set_interactive(false)
	_slot.add_child(cv)
	cv.setup(trap)
	_name.text = trap.definition.name
	_context.text = context
	for b in _buttons.get_children(): b.queue_free()
	_buttons.visible = interactive
	if interactive:
		for i in range(options.size()):
			var b := Button.new()
			b.text = options[i]
			var idx := i
			b.pressed.connect(func(): press_option(idx))
			_buttons.add_child(b)
			JuicyButton.apply(b)
	visible = true

func press_option(i: int) -> void:
	visible = false
	picked.emit(i)

func buttons_visible() -> bool:
	return _buttons.visible

func dismiss() -> void:
	visible = false
