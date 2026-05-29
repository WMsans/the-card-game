extends GdUnitTestSuite

func test_initial_state() -> void:
	var s := GameState.new(123)
	assert_array(s.players).has_size(2)
	assert_int(s.active_player).is_equal(0)
	assert_int(s.phase).is_equal(Enums.Phase.SETUP)
	assert_int(s.winner).is_equal(-1)
	assert_object(s.bus).is_not_null()
	assert_object(s.rng).is_not_null()

func test_opponent_and_active() -> void:
	var s := GameState.new(1)
	s.active_player = 1
	assert_int(s.opponent()).is_equal(0)
	assert_object(s.active()).is_same(s.players[1])

func test_make_instance_assigns_unique_ids() -> void:
	var s := GameState.new(1)
	var def := CardDefinition.new()
	var a := s.make_instance(def)
	var b := s.make_instance(def)
	assert_int(a.instance_id).is_not_equal(b.instance_id)

func test_player_defaults() -> void:
	var p := PlayerState.new()
	assert_int(p.reshuffles_remaining).is_equal(4)
	assert_int(p.available_tickets()).is_equal(0)
	assert_int(p.turn_counters["cards_played"]).is_equal(0)
