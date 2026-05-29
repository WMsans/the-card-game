extends GdUnitTestSuite

func _ready_engine() -> GameEngine:
	var state := GameState.new(11)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

func test_end_turn_passes_to_opponent_and_starts_their_turn() -> void:
	var eng := _ready_engine()
	var first := eng.state.active_player
	eng.apply(Action.end_turn())
	assert_int(eng.state.active_player).is_equal(1 - first)
	assert_int(eng.state.phase).is_equal(Enums.Phase.MAIN)

func test_end_turn_full_heals_damaged_units() -> void:
	var eng := _ready_engine()
	var ps := eng.state.active()
	var u := eng.state.make_instance(TestFactory.minion(1, 2, 5, 300))
	u.current_health = 1
	u.zone = Enums.Zone.BOARD
	ps.board.append(u)
	eng.apply(Action.end_turn())
	assert_int(u.current_health).is_equal(5)

func test_over_limit_hand_requires_discard_choice() -> void:
	var eng := _ready_engine()
	var ps := eng.state.active()
	while ps.hand.size() < 7:
		var c := eng.state.make_instance(TestFactory.minion(1, 1, 1, ps.hand.size()))
		c.zone = Enums.Zone.HAND
		ps.hand.append(c)
	eng.apply(Action.end_turn())
	assert_object(eng.state.pending_choice).is_not_null()
	assert_str(eng.state.pending_choice.kind).is_equal("discard_to_limit")
	assert_int(eng.state.pending_choice.data["count"]).is_equal(2)
	eng.apply(Action.resolve_choice({"indices": [0, 1]}))
	assert_int(ps.hand.size()).is_equal(5)
	assert_object(eng.state.pending_choice).is_null()
