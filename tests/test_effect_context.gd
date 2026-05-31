extends GdUnitTestSuite

func _eng() -> GameEngine:
	var state := GameState.new(2)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	return eng

func test_ctx_draw_moves_card_to_hand() -> void:
	var eng := _eng()
	var hand_before := eng.state.players[0].hand.size()
	var ctx = eng._ctx_for(0)
	ctx.draw(1)
	assert_int(eng.state.players[0].hand.size()).is_equal(hand_before + 1)

func test_ctx_me_and_opponent() -> void:
	var eng := _eng()
	var ctx = eng._ctx_for(0)
	assert_int(ctx.me()).is_equal(0)
	assert_int(ctx.opponent()).is_equal(1)

func test_search_deck_and_draw_specific() -> void:
	var eng := _eng()
	var ps := eng.state.players[0]
	var target := ps.deck[3]
	var found := eng._search_deck(0, func(c): return c.instance_id == target.instance_id)
	assert_object(found).is_equal(target)
	eng._draw_specific(0, found)
	assert_array(ps.hand).contains([target])
	assert_bool(ps.deck.has(target)).is_false()

func test_damage_unit_kills_at_zero() -> void:
	var eng := _eng()
	var u := eng.state.make_instance(TestFactory.minion(1, 1, 2, 700))
	u.zone = Enums.Zone.BOARD
	eng.state.players[0].board.append(u)
	eng._damage_unit(u, 2)
	assert_bool(eng.state.players[0].board.has(u)).is_false()
	assert_bool(eng.state.players[0].discard.has(u)).is_true()

func test_put_on_deck_top() -> void:
	var eng := _eng()
	var u := eng.state.make_instance(TestFactory.minion(1, 1, 1, 701))
	u.zone = Enums.Zone.BOARD
	eng.state.players[1].board.append(u)
	eng._put_on_deck_top(u)
	assert_object(eng.state.players[1].deck[0]).is_equal(u)
	assert_bool(eng.state.players[1].board.has(u)).is_false()

func test_steal_top_discard() -> void:
	var eng := _eng()
	var stolen := eng.state.make_instance(TestFactory.minion(1, 1, 1, 702))
	stolen.zone = Enums.Zone.DISCARD
	eng.state.players[1].discard.append(stolen)
	var got := eng._steal_top_discard(0, 1)
	assert_object(got).is_equal(stolen)
	assert_bool(eng.state.players[0].hand.has(stolen)).is_true()
	assert_int(stolen.vars["stolen_from"]).is_equal(1)
