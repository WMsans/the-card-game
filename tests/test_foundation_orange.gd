# tests/test_foundation_orange.gd
extends CardTestBase

func _oranges_in_hand(eng: GameEngine, p: int) -> int:
	var n := 0
	for c in eng.state.players[p].hand:
		if c.definition == OrangeToken.DEF:
			n += 1
	return n

func test_gain_orange_mints_into_hand() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var before := _oranges_in_hand(eng, me)
	EffectContext.new(eng, me).gain_orange(me)
	assert_int(_oranges_in_hand(eng, me)).is_equal(before + 1)

func test_gain_orange_capped_at_five() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ctx := EffectContext.new(eng, me)
	for i in range(8):
		ctx.gain_orange(me)
	assert_int(_oranges_in_hand(eng, me)).is_equal(5)

func test_orange_play_reduces_chosen_card_fee() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.tickets_total = 20
	var target := eng.state.make_instance(TestFactory.minion(5, 1, 1, 12))
	target.zone = Enums.Zone.HAND
	ps.hand.append(target)
	var orange := eng.state.make_instance(OrangeToken.DEF)
	orange.zone = Enums.Zone.HAND
	ps.hand.append(orange)
	eng.apply(Action.play_card(orange.instance_id))
	# Orange asks which hand card to discount
	assert_str(eng.state.pending_choice.data["ui_shape"]).is_equal("select_cards")
	var idx := ps.hand.find(target)
	eng.apply(Action.resolve_choice({"indices": [idx]}))
	assert_int(eng.effective_cost(target, me)).is_equal(4)

func test_orange_in_hand_raises_end_turn_limit() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.hand.clear()
	# 6 cards incl. one Orange -> limit 5 + 1 = 6, so no discard prompt
	for i in range(5):
		var c := eng.state.make_instance(TestFactory.minion(1, 1, 1, 400 + i))
		c.zone = Enums.Zone.HAND
		ps.hand.append(c)
	var orange := eng.state.make_instance(OrangeToken.DEF)
	orange.zone = Enums.Zone.HAND
	ps.hand.append(orange)
	eng.apply(Action.end_turn())
	assert_bool(eng.state.pending_choice != null and eng.state.pending_choice.kind == "discard_to_limit").is_false()
