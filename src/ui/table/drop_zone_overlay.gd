class_name DropZoneOverlay
extends Control

enum ZoneState { NEUTRAL, ACCEPTABLE, UNAFFORDABLE }

const DASH := 18.0
const GAP := 12.0

var _zones: Array[Rect2] = []
var _hovered: int = -1
var _state: int = ZoneState.NEUTRAL
var _bump: float = 0.0
var _bump_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func show_zones(rects: Array) -> void:
	_zones.clear()
	for r in rects:
		_zones.append(r)
	_hovered = -1
	_state = ZoneState.NEUTRAL
	visible = not _zones.is_empty()
	queue_redraw()

func set_hover(point: Vector2, state: int) -> void:
	var idx := _zone_at(point)
	if idx != _hovered and idx != -1:
		_kick_bump()
	_hovered = idx
	_state = state
	queue_redraw()

func is_hovering_zone() -> bool:
	return _hovered != -1

func clear() -> void:
	_zones.clear()
	_hovered = -1
	visible = false
	queue_redraw()

func _zone_at(point: Vector2) -> int:
	for i in _zones.size():
		if _zones[i].has_point(point):
			return i
	return -1

func _kick_bump() -> void:
	if _bump_tween and _bump_tween.is_running():
		_bump_tween.kill()
	_bump = 1.0
	_bump_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	var callable := func(v: float) -> void:
		_bump = v
		queue_redraw()
	_bump_tween.tween_method(callable, 1.0, 0.0, 0.45)

func _draw() -> void:
	for i in _zones.size():
		var hovered := i == _hovered
		var rect := _zones[i]
		var fill := UiPalette.ZONE_NEUTRAL
		if hovered:
			rect = rect.grow(_bump * 8.0)
			match _state:
				ZoneState.ACCEPTABLE: fill = UiPalette.ZONE_ACCEPTABLE
				ZoneState.UNAFFORDABLE: fill = UiPalette.ZONE_UNAFFORDABLE
				_: fill = UiPalette.ZONE_NEUTRAL
		draw_rect(rect, fill, true)
		_draw_dashed_border(rect, UiPalette.ZONE_OUTLINE, 4.0 if hovered else 3.0)

func _draw_dashed_border(rect: Rect2, color: Color, width: float) -> void:
	var corners := [
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	]
	for c in 4:
		_dashed_line(corners[c], corners[(c + 1) % 4], color, width)

func _dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var length := from.distance_to(to)
	var dir := (to - from).normalized()
	var travelled := 0.0
	while travelled < length:
		var seg := minf(DASH, length - travelled)
		draw_line(from + dir * travelled, from + dir * (travelled + seg), color, width)
		travelled += DASH + GAP