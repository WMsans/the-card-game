class_name CardFlight
extends RefCounted

const FLY_TIME := 0.34
const STAGGER := 0.06
const ARC_HEIGHT := 80.0

static func fly_in(cv: CardView, from_pos: Vector2, delay: float = 0.0) -> Tween:
	cv.position = from_pos
	var rest: Vector2 = cv._rest_position
	var mid := (from_pos + rest) * 0.5 + Vector2(0.0, -ARC_HEIGHT)
	var base := cv.base_scale
	var tw := cv.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(cv, "position", mid, FLY_TIME * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "position", rest, FLY_TIME * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cv, "scale", Vector2(base, base) * 1.12, FLY_TIME * 0.55).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(cv, "scale", Vector2(base, base), 0.12).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return tw

static func fly_out(cv: CardView, to_pos: Vector2, delay: float = 0.0) -> Tween:
	var base := cv.base_scale
	var tw := cv.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(cv, "position", to_pos, FLY_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cv, "scale", Vector2(base, base) * 0.7, FLY_TIME).set_trans(Tween.TRANS_CUBIC)
	return tw

static func move_to(cv: CardView, pos: Vector2, rot: float, delay: float = 0.0) -> Tween:
	var tw := cv.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(cv, "position", pos, FLY_TIME * 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "rotation", rot, FLY_TIME * 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw
