extends GdUnitTestSuite

func _started_engine(seed_value: int) -> GameEngine:
	var state := GameState.new(seed_value)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

func test_setup_draws_leader_into_hand() -> void:
	var state := GameState.new(7)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	assert_array(state.players[0].hand).has_size(6)
	assert_object(state.players[0].leader).is_not_null()

func test_pending_mulligan_is_set_for_player_zero_first() -> void:
	var state := GameState.new(7)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	assert_str(state.pending_choice.kind).is_equal("mulligan")
	assert_int(state.pending_choice.player).is_equal(0)

func test_after_both_mulligans_game_begins_in_main() -> void:
	var eng := _started_engine(7)
	assert_object(eng.state.pending_choice).is_null()
	assert_int(eng.state.phase).is_equal(Enums.Phase.MAIN)
	assert_int(eng.state.turn_number).is_equal(1)

func test_mulligan_reduces_hand_then_first_draw_restores() -> void:
	var eng := _started_engine(7)
	assert_array(eng.state.players[0].hand).has_size(5)

func test_first_player_gets_one_ticket_second_gets_two() -> void:
	var eng := _started_engine(7)
	var first := eng.state.first_player
	var second := 1 - first
	assert_int(eng.state.players[first].tickets_total).is_equal(1)
	assert_int(eng.state.players[second].tickets_total).is_equal(0)

func test_ticket_ramp_caps_at_ten() -> void:
	var ps := PlayerState.new()
	ps.tickets_total = 9
	ps.tickets_total = min(10, ps.tickets_total + 2)
	ps.tickets_total = min(10, ps.tickets_total + 2)
	assert_int(ps.tickets_total).is_equal(10)
