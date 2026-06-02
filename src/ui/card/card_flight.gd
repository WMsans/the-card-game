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

const FLOURISH_TIME := 0.42

# Pure: sample a quadratic Bezier (from -> control -> to) into `segments`+1 points.
# `control_offset` bends the path off the straight line so it reads as a sweep.
static func arc_points(from_pos: Vector2, to_pos: Vector2, control_offset: Vector2, segments: int = 8) -> PackedVector2Array:
	var control := (from_pos + to_pos) * 0.5 + control_offset
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var a := from_pos.lerp(control, t)
		var b := control.lerp(to_pos, t)
		pts.append(a.lerp(b, t))
	return pts

# Fly a card along the sampled curve, scaling down slightly as it lands.
static func flourish_arc(cv: CardView, to_pos: Vector2, control_offset: Vector2, speed: float = 1.0) -> Tween:
	var base := cv.base_scale
	var pts := arc_points(cv.position, to_pos, control_offset, 8)
	var dur: float = FLOURISH_TIME / maxf(speed, 0.01)
	var seg_time: float = dur / float(pts.size() - 1)
	var st := cv.create_tween()
	st.tween_property(cv, "scale", Vector2(base, base) * 0.55, dur).set_trans(Tween.TRANS_QUAD)
	var tw := cv.create_tween()
	for i in range(1, pts.size()):
		tw.tween_property(cv, "position", pts[i], seg_time).set_trans(Tween.TRANS_LINEAR)
	return tw

const ORBIT_TIME := 0.9
const ORBIT_RADIUS := 280.0
const ORBIT_SEGMENTS := 16

# Pure: sample a full circle around `center` starting at `start_angle`, returning
# `segments`+1 points (the last equals the first, closing the loop).
static func circle_points(center: Vector2, radius: float, start_angle: float, segments: int = ORBIT_SEGMENTS) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var a := start_angle + TAU * (float(i) / float(segments))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts

# Fly out from the card's current spot into a full 360° loop around `center`,
# then dart into `to_pos`, scaling down as it lands. Card facing is unchanged.
static func orbit_loop(cv: CardView, center: Vector2, radius: float, to_pos: Vector2, speed: float = 1.0) -> Tween:
	var base := cv.base_scale
	var pts := circle_points(center, radius, -PI / 2.0, ORBIT_SEGMENTS)
	var dur: float = ORBIT_TIME / maxf(speed, 0.01)
	# One segment to fly out, ORBIT_SEGMENTS around the ring, one to dart in.
	var seg: float = dur / float(ORBIT_SEGMENTS + 2)
	var tw := cv.create_tween()
	tw.tween_property(cv, "position", pts[0], seg).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for i in range(1, pts.size()):
		tw.tween_property(cv, "position", pts[i], seg).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(cv, "position", to_pos, seg).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var st := cv.create_tween()
	st.tween_property(cv, "scale", Vector2(base, base) * 0.55, dur).set_trans(Tween.TRANS_QUAD)
	return tw
