extends Node2D

var active: bool = false
var start: Vector2
var target: Vector2

func begin(from: Vector2) -> void:
	active = true
	start = from
	target = from
	queue_redraw()

func point_at(to: Vector2) -> void:
	target = to
	queue_redraw()

func end() -> void:
	active = false
	queue_redraw()

func _curve_point(t: float) -> Vector2:
	var ctrl := start.lerp(target, 0.5) + Vector2(0, -120)
	return start.lerp(ctrl, t).lerp(ctrl.lerp(target, t), t)

func _draw() -> void:
	if not active:
		return
	var pts: PackedVector2Array = []
	for i in range(21):
		pts.append(_curve_point(float(i) / 20.0))
	draw_polyline(pts, Color(1, 0.9, 0.3), 4.0)
	draw_circle(target, 8.0, Color(1, 0.9, 0.3))