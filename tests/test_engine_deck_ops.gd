extends GdUnitTestSuite

func _engine_with_deck(n_cards: int) -> GameEngine:
	var state := GameState.new(1)
	var eng := GameEngine.new(state)
	for i in range(n_cards):
		var ci := state.make_instance(TestFactory.minion(1, 1, 1, i))
		ci.zone = Enums.Zone.DECK
		state.players[0].deck.append(ci)
	return eng

func test_draw_moves_card_to_hand() -> void:
	var eng := _engine_with_deck(5)
	eng._draw(0, 2)
	assert_array(eng.state.players[0].hand).has_size(2)
	assert_array(eng.state.players[0].deck).has_size(3)

func test_mill_moves_cards_to_discard() -> void:
	var eng := _engine_with_deck(5)
	eng._mill(0, 3)
	assert_array(eng.state.players[0].discard).has_size(3)
	assert_array(eng.state.players[0].deck).has_size(2)

func test_empty_deck_reshuffles_discard() -> void:
	var eng := _engine_with_deck(2)
	eng._mill(0, 2)
	eng._draw(0, 1)
	var p := eng.state.players[0]
	assert_int(p.reshuffles_remaining).is_equal(3)
	assert_array(p.hand).has_size(1)

func test_running_out_of_reshuffles_loses() -> void:
	var eng := _engine_with_deck(1)
	var p := eng.state.players[0]
	p.reshuffles_remaining = 0
	eng._mill(0, 1)
	eng._draw(0, 1)
	assert_int(eng.state.phase).is_equal(Enums.Phase.GAME_OVER)
	assert_int(eng.state.winner).is_equal(1)
