class_name FeedbackFx
extends RefCounted

const CHAIN_GAP := 0.6
const RAMP_STEP := 0.35
const MAX_SPEED := 2.5
const PILE_BUMP_UP := 0.08
const PILE_BUMP_DOWN := 0.12
const HOLD_TIME := 2.0

static func next_speed(current: float, gap: float) -> float:
	if gap <= CHAIN_GAP:
		return minf(current + RAMP_STEP, MAX_SPEED)
	return 1.0

static func bump_pile(pile: Control, spd: float) -> void:
	if pile == null:
		return
	var s: Vector2 = pile.scale
	var tw: Tween = pile.create_tween()
	tw.tween_property(pile, "scale", s * 1.18, PILE_BUMP_UP / maxf(spd, 0.01)).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(pile, "scale", s, PILE_BUMP_DOWN / maxf(spd, 0.01)).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
