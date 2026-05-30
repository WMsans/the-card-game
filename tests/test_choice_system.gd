extends GdUnitTestSuite

func test_choice_spec_select_cards_shape() -> void:
	var spec := ChoiceSpec.select_cards([], 0, 3, "Pick")
	assert_str(spec.ui_shape).is_equal("select_cards")
	assert_int(spec.min_n).is_equal(0)
	assert_int(spec.max_n).is_equal(3)
	assert_str(spec.title).is_equal("Pick")

func test_choice_spec_choose_option_shape() -> void:
	var spec := ChoiceSpec.choose_option(["A", "B"], "Decide")
	assert_str(spec.ui_shape).is_equal("choose_option")
	assert_array(spec.labels).is_equal(["A", "B"])

func test_choice_spec_select_target_shape() -> void:
	var spec := ChoiceSpec.select_target([], 1, 1, "Target")
	assert_str(spec.ui_shape).is_equal("select_target")
	assert_int(spec.min_n).is_equal(1)
	assert_int(spec.max_n).is_equal(1)
	assert_str(spec.title).is_equal("Target")

class AskScript extends CardScript:
	func on_cast(card, ctx) -> void:
		ctx.request_choice(card, ChoiceSpec.select_cards(ctx.hand(ctx.me()), 0, 9, "Pick"), "pick")
	func resume(card, tag, result, ctx) -> void:
		if tag == "pick":
			ctx.draw(result["cards"].size() + 1)

func _engine_after_mulligan() -> GameEngine:
	var state := GameState.new(9)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([]))
	eng.apply(Action.mulligan([]))
	return eng

func test_request_choice_suspends_then_resumes() -> void:
	var eng := _engine_after_mulligan()
	var ps := eng.state.active()
	var card := eng.state.make_instance(TestFactory.minion(0, 1, 1, 950))
	card.card_script = AskScript.new()
	card.zone = Enums.Zone.BOARD
	ps.board.append(card)
	eng._push({"kind": "call", "fn": func(): card.card_script.on_cast(card, eng._ctx_for(eng.state.active_player))})
	eng._pump()
	assert_object(eng.state.pending_choice).is_not_null()
	assert_str(eng.state.pending_choice.kind).is_equal("card_effect")
	assert_bool(eng._suspended).is_true()
	var hand_before := ps.hand.size()
	eng.apply(Action.resolve_choice({"indices": [0]}))
	assert_object(eng.state.pending_choice).is_null()
	assert_bool(eng._suspended).is_false()
	assert_int(ps.hand.size()).is_equal(hand_before + 2)
