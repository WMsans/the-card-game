extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _a_card() -> CardView:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m.hand_view.card_views.values()[0]

func test_flip_reveals_face_up_and_restores_scale() -> void:
	var cv := _a_card()
	cv.set_face_down(true)
	assert_bool(cv._face_down).is_true()
	var t: Tween = cv.flip_to_face_up()
	await t.finished
	assert_bool(cv._face_down).is_false()
	assert_float(cv.get_node("CardSurface").scale.x).is_equal_approx(1.0, 0.01)
