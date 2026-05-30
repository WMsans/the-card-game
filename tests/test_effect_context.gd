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
