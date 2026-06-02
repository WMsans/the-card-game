extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

# A real CardView from a populated hand (base_scale already set to CARD_SCALE).
# Wait out the initial render tween so it can't race the flight tween under test.
func _a_card() -> CardView:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	await get_tree().create_timer(0.35).timeout
	return m.hand_view.card_views.values()[0]

func test_fly_in_starts_at_source_and_lands_at_rest() -> void:
	var cv := await _a_card()
	cv.set_rest(Vector2(500, 900), 0.0)
	var tw := CardFlight.fly_in(cv, Vector2(1700, 800))
	# Placed at the source synchronously, before the tween steps.
	assert_vector(cv.position).is_equal_approx(Vector2(1700, 800), Vector2(1, 1))
	await tw.finished
	assert_vector(cv.position).is_equal_approx(Vector2(500, 900), Vector2(1.5, 1.5))
	assert_float(cv.scale.x).is_equal_approx(cv.base_scale, 0.02)

func test_fly_out_moves_to_destination() -> void:
	var cv := await _a_card()
	var tw := CardFlight.fly_out(cv, Vector2(1700, 600))
	await tw.finished
	assert_vector(cv.position).is_equal_approx(Vector2(1700, 600), Vector2(1.5, 1.5))

func test_move_to_reaches_target() -> void:
	var cv := await _a_card()
	var tw := CardFlight.move_to(cv, Vector2(700, 850), 0.0)
	await tw.finished
	assert_vector(cv.position).is_equal_approx(Vector2(700, 850), Vector2(2, 2))

func test_flourish_arc_samples_a_curved_path() -> void:
	var from := Vector2(960, 540)
	var to := Vector2(1735, 855)
	var pts: PackedVector2Array = CardFlight.arc_points(from, to, Vector2(0, -260), 6)
	# Endpoints honored.
	assert_vector(pts[0]).is_equal_approx(from, Vector2(0.5, 0.5))
	assert_vector(pts[pts.size() - 1]).is_equal_approx(to, Vector2(0.5, 0.5))
	# A genuine curve: the midpoint sits off the straight line between endpoints.
	var mid: Vector2 = pts[pts.size() / 2]
	var straight := from.lerp(to, 0.5)
	assert_float(mid.distance_to(straight)).is_greater(20.0)

func test_circle_points_ring_around_center() -> void:
	var center := Vector2(960, 540)
	var pts: PackedVector2Array = CardFlight.circle_points(center, 280.0, -PI / 2.0, 16)
	assert_int(pts.size()).is_equal(17)            # segments + 1 (closes the loop)
	for p in pts:
		assert_float(p.distance_to(center)).is_equal_approx(280.0, 0.5)
	# Loop closes back onto its start.
	assert_vector(pts[0]).is_equal_approx(pts[pts.size() - 1], Vector2(0.5, 0.5))

func test_orbit_loop_ends_at_destination() -> void:
	var cv := await _a_card()
	cv.position = Vector2(960, 540)
	var to_pos := Vector2(1735, 855)
	var tw := CardFlight.orbit_loop(cv, cv.position, 280.0, to_pos, 1.0)
	await tw.finished
	assert_vector(cv.position).is_equal_approx(to_pos, Vector2(2, 2))
