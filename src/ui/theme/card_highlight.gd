class_name CardHighlight
extends Control

enum State { NONE, PLAYABLE, ATTACKABLE, SELECTABLE, SELECTED }

const _COLORS := {
	State.PLAYABLE: UiPalette.HL_PLAYABLE,
	State.ATTACKABLE: UiPalette.HL_ATTACKABLE,
	State.SELECTABLE: UiPalette.HL_SELECTABLE,
	State.SELECTED: UiPalette.HL_SELECTED,
}

var _state: int = State.NONE
var _color: Color = Color.TRANSPARENT
var _pulse: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func set_state(state: int) -> void:
	_state = state
	visible = state != State.NONE
	if visible:
		_color = _COLORS[state]
	queue_redraw()

func current_color() -> Color:
	return _color

func _process(delta: float) -> void:
	if not visible:
		return
	_pulse = fmod(_pulse + delta * 3.0, TAU)
	queue_redraw()

func _draw() -> void:
	if _state == State.NONE:
		return
	var a := 0.55 + 0.35 * sin(_pulse)
	var border := Color(_color.r, _color.g, _color.b, a)
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, border, false, 6.0)
	draw_rect(rect.grow(-3.0), Color(_color.r, _color.g, _color.b, a * 0.15), true)