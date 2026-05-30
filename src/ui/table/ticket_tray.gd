class_name TicketTray
extends HBoxContainer

const PIP_FILLED := Color(0.95, 0.8, 0.2)
const PIP_EMPTY := Color(0.3, 0.3, 0.3)

var _tapped: int = 0
var _total: int = 0

func set_tickets(tapped: int, total: int) -> void:
	_tapped = tapped
	_total = total
	for c in get_children():
		c.queue_free()
	for i in range(total):
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(28, 28)
		pip.color = PIP_FILLED if i < (total - tapped) else PIP_EMPTY
		add_child(pip)

func filled_count() -> int:
	var n := 0
	for c in get_children():
		if c is ColorRect and c.color == PIP_FILLED:
			n += 1
	return n
