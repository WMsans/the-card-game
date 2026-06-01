extends GdUnitTestSuite

func _state_in_main(seed_value: int) -> Array:
	var st := GameState.new(seed_value)
	var en := GameEngine.new(st)
	en.setup(CardDatabase.load_deck("res://src/data/decks/strike.csv", "S"),
			 CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "R"))
	while st.pending_choice != null:
		en.apply(Action.mulligan([0, 1]))
	return [st, en]

func test_drop_on_play_zone_yields_play_card_when_legal() -> void:
	var pair := _state_in_main(3)
	var st: GameState = pair[0]
	var en: GameEngine = pair[1]
	var legal: Array = en.get_legal_actions()
	var play := legal.filter(func(a): return a.type == Enums.ActionType.PLAY_CARD)
	if play.is_empty():
		return
	var iid: int = play[0].params["instance_id"]
	var act = CardInput.play_from_drop(iid, "play_zone", legal)
	if act == null:
		act = CardInput.play_from_drop(iid, "play_zone", legal, true)
	assert_object(act).is_not_null()
	assert_int(act.type).is_equal(Enums.ActionType.PLAY_CARD)

func test_illegal_play_returns_null() -> void:
	var pair := _state_in_main(3)
	var en: GameEngine = pair[1]
	assert_object(CardInput.play_from_drop(99999, "play_zone", en.get_legal_actions())).is_null()

func test_attack_target_unit_yields_declare_attack() -> void:
	var act = CardInput.attack_from_target(5, {"unit": 8},
		[Action.declare_attack(5, {"unit": 8})])
	assert_object(act).is_not_null()
	assert_int(act.type).is_equal(Enums.ActionType.DECLARE_ATTACK)

func test_attack_deck_target() -> void:
	var act = CardInput.attack_from_target(5, {"deck": true},
		[Action.declare_attack(5, {"deck": true})])
	assert_object(act).is_not_null()