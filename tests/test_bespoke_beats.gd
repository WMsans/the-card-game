extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"
const STRIKE := "res://src/data/decks/strike.csv"

func _match() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, STRIKE, STRIKE)
	await get_tree().create_timer(0.35).timeout
	return m

func _hand_card(m: Node, iid: int, type: int) -> CardView:
	var d := CardDefinition.new()
	d.type = type
	d.name = "Test"
	var inst := CardInstance.new(iid, d)
	inst.zone = Enums.Zone.HAND
	m.hand_view.render([inst], 0)
	await get_tree().create_timer(0.35).timeout
	return m.hand_view.card_views[iid]

func test_spell_feature_moves_card_toward_center() -> void:
	var m := await _match()
	var cv := await _hand_card(m, 301, Enums.CardType.SPELL)
	# Start the beat; sample position partway through the hold.
	m._feature_spell(301, 0)
	await get_tree().create_timer(0.4).timeout
	var center := Vector2(BoardLayout.CENTER_X, BoardLayout.SCREEN.y * 0.5)
	# It should be much closer to center than a hand card's resting Y (~940).
	assert_float(cv.global_position.y).is_less(700.0)

func test_trap_deploy_flips_card_face_down() -> void:
	var m := await _match()
	var cv := await _hand_card(m, 311, Enums.CardType.TRAP)
	assert_bool(cv._face_down).is_false()
	m._feature_trap_deploy(311, 0)
	# Past the center hold + the arc; the card should have flipped face-down en route.
	await get_tree().create_timer(FeedbackFx.HOLD_TIME + 0.8).timeout
	assert_bool(cv._face_down).is_true()

func test_run_feedback_features_a_played_spell() -> void:
	var m := await _match()
	var cv := await _hand_card(m, 321, Enums.CardType.SPELL)
	var events := [GameEvent.new(Enums.EventType.CARD_PLAYED,
		{"player": 0, "instance": 321, "card_type": Enums.CardType.SPELL})]
	m._run_bespoke(events)
	await get_tree().create_timer(0.4).timeout
	assert_float(cv.global_position.y).is_less(700.0)

func test_handle_drop_marks_card_played() -> void:
	var m := await _match()
	var cv := await _hand_card(m, 401, Enums.CardType.SPELL)
	m._find_card_view_any(401).mark_played()
	assert_bool(cv._consumed).is_true()
