extends GdUnitTestSuite

func _state_in_main(seed_value: int) -> Array:
	var st := GameState.new(seed_value)
	var en := GameEngine.new(st)
	en.setup(CardDatabase.load_deck("res://src/data/decks/strike.csv", "S"),
			 CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "R"))
	while st.pending_choice != null:
		en.apply(Action.mulligan([0, 1]))
	return [st, en]

func test_legal_play_is_acceptable() -> void:
	var pair := _state_in_main(3)
	var st: GameState = pair[0]
	var en: GameEngine = pair[1]
	var legal := en.get_legal_actions()
	var plays := legal.filter(func(a): return a.type == Enums.ActionType.PLAY_CARD)
	if plays.is_empty():
		return
	var iid: int = plays[0].params["instance_id"]
	assert_int(DragClassifier.classify(st, legal, iid, 0)).is_equal(DragClassifier.State.ACCEPTABLE)

func test_card_not_in_hand_is_invalid() -> void:
	var pair := _state_in_main(3)
	var st: GameState = pair[0]
	var en: GameEngine = pair[1]
	assert_int(DragClassifier.classify(st, en.get_legal_actions(), 999999, 0)).is_equal(DragClassifier.State.INVALID)

func test_not_your_turn_is_invalid() -> void:
	var pair := _state_in_main(3)
	var st: GameState = pair[0]
	var en: GameEngine = pair[1]
	var iid: int = st.players[0].hand[0].instance_id
	st.active_player = 1
	assert_int(DragClassifier.classify(st, en.get_legal_actions(), iid, 0)).is_equal(DragClassifier.State.INVALID)

func test_too_few_tickets_is_unaffordable() -> void:
	var pair := _state_in_main(3)
	var st: GameState = pair[0]
	var en: GameEngine = pair[1]
	var iid := -1
	for c in st.players[0].hand:
		if c.definition.type != Enums.CardType.LEADER and c.definition.ticket_cost > 0:
			iid = c.instance_id
			break
	if iid == -1:
		return
	st.players[0].tickets_tapped = st.players[0].tickets_total
	assert_int(DragClassifier.classify(st, en.get_legal_actions(), iid, 0)).is_equal(DragClassifier.State.UNAFFORDABLE)

func test_advertises_zone_for_hand_card_on_turn() -> void:
	var pair := _state_in_main(3)
	var st: GameState = pair[0]
	var iid := -1
	for c in st.players[0].hand:
		if c.definition.type != Enums.CardType.LEADER:
			iid = c.instance_id
			break
	if iid == -1:
		return
	assert_bool(DragClassifier.advertises_zone(st, iid, 0)).is_true()