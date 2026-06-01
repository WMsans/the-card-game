class_name CardJuice
extends RefCounted

const WINDUP_TIME := 0.12
const LUNGE_TIME := 0.14
const RECOIL_TIME := 0.24
const SQUASH_TIME := 0.10
const POP_TIME := 0.18
const HITSTOP := 0.05
const WIGGLE_TIME := 0.5

static func _t(base_time: float, speed: float) -> float:
	return base_time / maxf(speed, 0.01)

static func windup(cv: CardView, to_pos: Vector2, speed: float = 1.0) -> Tween:
	var base := cv.base_scale
	var t := _t(WINDUP_TIME, speed)
	var tw := cv.create_tween().set_parallel(true)
	tw.tween_property(cv, "position", to_pos, t).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2(base, base) * 1.08, t).set_trans(Tween.TRANS_QUAD)
	return tw

static func lunge(cv: CardView, to_pos: Vector2, speed: float = 1.0) -> Tween:
	var tw := cv.create_tween()
	tw.tween_property(cv, "position", to_pos, _t(LUNGE_TIME, speed)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	return tw

static func recoil(cv: CardView, to_pos: Vector2, rot: float, speed: float = 1.0) -> Tween:
	var base := cv.base_scale
	var t := _t(RECOIL_TIME, speed)
	var tw := cv.create_tween().set_parallel(true)
	tw.tween_property(cv, "position", to_pos, t).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "rotation", rot, t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2(base, base), t).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return tw

static func squash(cv: CardView, speed: float = 1.0) -> Tween:
	var base := cv.base_scale
	var t := _t(SQUASH_TIME, speed)
	var tw := cv.create_tween()
	tw.tween_property(cv, "scale", Vector2(1.18, 0.82) * base, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2(base, base), t).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return tw

static func pop(cv: CardView, speed: float = 1.0) -> Tween:
	var base := cv.base_scale
	var t := _t(POP_TIME, speed)
	var tw := cv.create_tween()
	tw.tween_property(cv, "scale", Vector2(base, base) * 1.35, t * 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cv, "modulate", Color(1.6, 1.6, 1.6), t * 0.45)
	tw.tween_property(cv, "scale", Vector2(base, base), t * 0.55).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(cv, "modulate", Color.WHITE, t * 0.55)
	return tw

# Balatro joker-trigger feel: tilt a few degrees, then elastically spring back to upright.
static func spring_wiggle(cv: CanvasItem, degrees: float = 9.0, speed: float = 1.0) -> Tween:
	var start: float = cv.rotation
	var t := _t(WIGGLE_TIME, speed)
	var tw := cv.create_tween()
	tw.tween_property(cv, "rotation", start + deg_to_rad(degrees), t * 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "rotation", start, t * 0.75).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return tw
