# src/ui/overlays/trap_reveal_overlay.gd
extends CanvasLayer

signal picked(option: int)
signal minimize_requested

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

@onready var _slot: Control = $Center/Panel/Margin/VBox/Body/CardSlot
@onready var _name: Label = $Center/Panel/Margin/VBox/TrapName
@onready var _context: Label = $Center/Panel/Margin/VBox/Body/Context
@onready var _buttons: HBoxContainer = $Center/Panel/Margin/VBox/Buttons

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

func _ready() -> void:
	var _min_btn: Button = $Center/Panel/Margin/VBox/MinimizeButton
	JuicyButton.apply(_min_btn)
	_min_btn.pressed.connect(func(): minimize_requested.emit())

func dismiss() -> void:
	visible = false

func get_animatable_nodes() -> Array[Node]:
	return [_name, $Center/Panel/Margin/VBox/Body, _buttons, $Center/Panel/Margin/VBox/MinimizeButton]

func get_dim_node() -> ColorRect:
	return $Dim
