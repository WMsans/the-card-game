extends Node2D

# Owns cards no zone owns while airborne: reparented leavers (death/discard) and
# pile->pile travelers (mill/reshuffle). Each self-frees on landing. Lives under
# Table so its coordinate space matches the hand/board views and pile centers.

const CARD_VIEW := preload("res://src/ui/card/card_view.tscn")

var _placeholder: CardDefinition

func _ready() -> void:
	_placeholder = CardDefinition.new()
	_placeholder.name = "?"

# Reparent a zone's card here (keeping its global position) and fly it to a pile.
func take_leaver(cv: CardView, to_pos: Vector2, delay: float = 0.0) -> void:
	if cv.get_parent() != null:
		cv.reparent(self)
	var tw := CardFlight.fly_out(cv, to_pos, delay)
	tw.finished.connect(cv.queue_free)

# Spawn a fresh face-down traveler for a pile->pile move. `inst` may be the real
# card (mill) or null (reshuffle placeholder). Pile-to-pile transitions never flip.
func spawn_traveler(inst: CardInstance, from_pos: Vector2, to_pos: Vector2,
		delay: float = 0.0) -> CardView:
	var cv: CardView = CARD_VIEW.instantiate()
	add_child(cv)
	cv.set_interactive(false)
	cv.setup(inst if inst != null else CardInstance.new(-1, _placeholder))
	cv.set_base_scale(BoardLayout.CARD_SCALE)
	cv.set_face_down(true)
	cv.position = from_pos
	var tw := cv.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(cv, "position", to_pos, CardFlight.FLY_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(cv.queue_free)
	return cv