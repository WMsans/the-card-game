class_name TicketTray
extends HBoxContainer

var _tapped: int = 0
var _total: int = 0
var _pips: Array[ColorRect] = []

func set_tickets(tapped: int, total: int) -> void:
	var grew := total > _total
	_tapped = tapped
	_total = total
	for c in get_children():
		c.queue_free()
	_pips.clear()
	var available := total - tapped
	for i in range(total):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(28, 28)
		pip.pivot_offset = Vector2(14, 14)
		pip.color = UiPalette.PIP_FILLED if i < available else UiPalette.PIP_EMPTY
		add_child(pip)
		_pips.append(pip)
		_pop(pip, grew)

func filled_count() -> int:
	return _total - _tapped

func preview_cost(n: int) -> void:
	clear_preview()
	var available := _total - _tapped
	var k := mini(n, available)
	for i in range(available - k, available):
		if i >= 0 and i < _pips.size():
			_pips[i].color = UiPalette.PIP_COST
			_pop(_pips[i], true)

func clear_preview() -> void:
	var available := _total - _tapped
	for i in _pips.size():
		_pips[i].color = UiPalette.PIP_FILLED if i < available else UiPalette.PIP_EMPTY

func _pop(pip: ColorRect, grew: bool) -> void:
	if not is_inside_tree():
		return
	pip.scale = Vector2.ONE * (0.2 if grew else 0.8)
	var t := pip.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(pip, "scale", Vector2.ONE, 0.25)