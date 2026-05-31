extends GdUnitTestSuite

func _engine() -> GameEngine:
	var state := GameState.new(2)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([0, 1]))
	eng.apply(Action.mulligan([0, 1]))
	return eng

func _types(actions: Array) -> Array:
	return actions.map(func(a: Action): return a.type)

func test_pending_choice_yields_no_actions() -> void:
	var state := GameState.new(2)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	assert_array(eng.get_legal_actions()).is_empty()

func test_main_phase_offers_end_turn() -> void:
	var eng := _engine()
	assert_array(_types(eng.get_legal_actions())).contains([Enums.ActionType.END_TURN])

func test_affordable_card_is_playable_unaffordable_is_not() -> void:
	var eng := _engine()
	var ps := eng.state.active()
	ps.hand.clear()
	ps.tickets_total = 2
	ps.tickets_tapped = 0
	var cheap := eng.state.make_instance(TestFactory.minion(2, 1, 1, 600))
	cheap.zone = Enums.Zone.HAND
	ps.hand.append(cheap)
	var pricey := eng.state.make_instance(TestFactory.minion(9, 1, 1, 601))
	pricey.zone = Enums.Zone.HAND
	ps.hand.append(pricey)
	var ids := eng.get_legal_actions() \
		.filter(func(a: Action): return a.type == Enums.ActionType.PLAY_CARD) \
		.map(func(a: Action): return a.params["instance_id"])
	assert_array(ids).contains([cheap.instance_id])
	assert_array(ids).not_contains([pricey.instance_id])

func test_untapped_unit_can_attack_deck_and_enemy_units() -> void:
	var eng := _engine()
	var me := eng.state.active_player
	var opp := eng.state.opponent()
	var ps := eng.state.active()
	ps.hand.clear()
	var atk := eng.state.make_instance(TestFactory.minion(1, 1, 1, 602))
	atk.zone = Enums.Zone.BOARD
	atk.tapped = false
	ps.board.append(atk)
	var enemy := eng.state.make_instance(TestFactory.minion(1, 1, 1, 603))
	enemy.zone = Enums.Zone.BOARD
	eng.state.players[opp].board.append(enemy)
	var attacks := eng.get_legal_actions().filter(
		func(a: Action): return a.type == Enums.ActionType.DECLARE_ATTACK)
	assert_array(attacks).has_size(2)

func test_tapped_unit_cannot_attack() -> void:
	var eng := _engine()
	var ps := eng.state.active()
	ps.hand.clear()
	var atk := eng.state.make_instance(TestFactory.minion(1, 1, 1, 604))
	atk.zone = Enums.Zone.BOARD
	atk.tapped = true
	ps.board.append(atk)
	var attacks := eng.get_legal_actions().filter(
		func(a: Action): return a.type == Enums.ActionType.DECLARE_ATTACK)
	assert_array(attacks).is_empty()

class TapAbility extends CardScript:
	func activated_abilities(card, ctx) -> Array:
		if card.tapped: return []
		return [{"id": "go", "label": "Go"}]
	func activate(card, ability_id, ctx) -> void:
		if ability_id == "go": card.tapped = true

func test_activated_ability_listed_and_applied() -> void:
	var state := GameState.new(15)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([]))
	eng.apply(Action.mulligan([]))
	var u := state.make_instance(TestFactory.minion(1, 1, 1, 610))
	u.card_script = TapAbility.new()
	u.zone = Enums.Zone.BOARD
	u.tapped = false
	state.active().board.append(u)
	var legal := eng.get_legal_actions()
	var has_ability := false
	for a in legal:
		if a.type == Enums.ActionType.ACTIVATE_ABILITY and a.params["instance_id"] == u.instance_id:
			has_ability = true
	assert_bool(has_ability).is_true()
	eng.apply(Action.activate_ability(u.instance_id, "go"))
	assert_bool(u.tapped).is_true()
