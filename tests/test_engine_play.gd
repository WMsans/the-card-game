extends GdUnitTestSuite

func _ready_engine() -> GameEngine:
	var state := GameState.new(5)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

func _give(eng: GameEngine, def: CardDefinition) -> CardInstance:
	var ps := eng.state.active()
	var ci := eng.state.make_instance(def)
	ci.zone = Enums.Zone.HAND
	ps.hand.append(ci)
	ps.tickets_total = 10
	ps.tickets_tapped = 0
	return ci

func test_play_minion_enters_board_tapped_and_pays_tickets() -> void:
	var eng := _ready_engine()
	var ci := _give(eng, TestFactory.minion(3, 4, 4, 200))
	eng.apply(Action.play_card(ci.instance_id))
	var ps := eng.state.active()
	assert_array(ps.board).contains([ci])
	assert_bool(ci.tapped).is_true()
	assert_int(ps.tickets_tapped).is_equal(3)
	assert_int(ps.turn_counters["cards_played"]).is_equal(1)

func test_play_spell_goes_to_discard() -> void:
	var eng := _ready_engine()
	var ci := _give(eng, TestFactory.spell(2, 201))
	eng.apply(Action.play_card(ci.instance_id))
	assert_array(eng.state.active().discard).contains([ci])

func test_play_trap_is_set_face_down() -> void:
	var eng := _ready_engine()
	var ci := _give(eng, TestFactory.trap(2, 202))
	eng.apply(Action.play_card(ci.instance_id))
	assert_array(eng.state.active().set_traps).contains([ci])
	assert_int(ci.zone).is_equal(Enums.Zone.TRAP_SET)

func test_play_leader_by_discard_cost_mills_deck() -> void:
	var eng := _ready_engine()
	var ci := _give(eng, TestFactory.leader(7, 2, 5, 4))
	var deck_before := eng.state.active().deck.size()
	eng.apply(Action.play_card(ci.instance_id, {"pay_by_discard": true}))
	var ps := eng.state.active()
	assert_array(ps.board).contains([ci])
	assert_int(ps.tickets_tapped).is_equal(0)
	assert_int(ps.deck.size()).is_equal(deck_before - 4)

class CastBattlecry extends CardScript:
	func on_cast(card, ctx) -> void: ctx.draw(1)

func test_on_cast_battlecry_runs_when_played() -> void:
	var eng := _ready_engine()
	var ci := _give(eng, TestFactory.minion(1, 1, 1, 210))
	ci.card_script = CastBattlecry.new()
	var hand_before := eng.state.active().hand.size()
	eng.apply(Action.play_card(ci.instance_id))
	assert_int(eng.state.active().hand.size()).is_equal(hand_before)
