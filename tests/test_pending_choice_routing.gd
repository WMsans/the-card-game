extends GdUnitTestSuite

func _spawn_with_mulligan() -> Node:
	var m: Node = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/raccoon.csv")
	return m

func _spawn() -> Node:
	var m := _spawn_with_mulligan()
	var hand: Array = m.state.players[0].hand
	var hc = m._hand_choice
	var clicked := 0
	for i in range(hand.size()):
		if hand[i].definition.type != Enums.CardType.LEADER and clicked < 2:
			hc._on_card_clicked(hand[i].instance_id)
			clicked += 1
	hc._confirm_pressed()
	return m

func test_human_mulligan_shows_panel_ai_resolves_automatically() -> void:
	var m: Node = _spawn_with_mulligan()
	assert_bool(m._hand_choice.visible).is_true()
	m._hand_choice.confirmed.emit([0, 1])
	await get_tree().create_timer(0.6).timeout
	assert_bool(m.state.pending_choice == null).is_true()

func test_game_over_panel_shows_on_game_over() -> void:
	var m: Node = _spawn()
	m.state.phase = Enums.Phase.GAME_OVER
	m.state.winner = 0
	m._show_game_over()
	assert_bool(m.get_node("GameOverPanel").visible).is_true()

func test_hand_pool_select_cards_uses_hand_choice() -> void:
	var m: Node = _spawn()
	m.state.pending_choice = PendingChoice.new("card_effect", 0, {"spec": ChoiceSpec.select_cards(m.state.players[0].hand, 0, 1, "Pick"), "ui_shape": "select_cards"})
	m._route_pending_choice()
	assert_bool(m.get_node("HandChoice").visible).is_true()
	assert_bool(m.get_node("CardSelectPanel").visible).is_false()

func test_non_hand_pool_select_cards_uses_overlay() -> void:
	var m: Node = _spawn()
	var def: CardDefinition = m.state.players[0].hand[0].definition
	var outsider := CardInstance.new(999999, def)
	var spec := ChoiceSpec.select_cards([outsider], 0, 1, "Pick")
	m.state.pending_choice = PendingChoice.new("card_effect", 0, {"spec": spec, "ui_shape": "select_cards"})
	m._route_pending_choice()
	assert_bool(m.get_node("CardSelectPanel").visible).is_true()
	assert_bool(m.get_node("HandChoice").visible).is_false()

func test_discard_to_limit_resolves_through_hand_choice() -> void:
	var m: Node = _spawn()
	var hand: Array = m.state.players[0].hand
	var id0: int = hand[0].instance_id
	var id1: int = hand[1].instance_id
	m.state.pending_choice = PendingChoice.new("discard_to_limit", 0, {"count": 2})
	m._route_pending_choice()
	assert_bool(m.get_node("HandChoice").visible).is_true()
	m._hand_choice._on_card_clicked(id0)
	m._hand_choice._on_card_clicked(id1)
	m._hand_choice._confirm_pressed()
	assert_bool(m.state.pending_choice == null).is_true()
	var discard_ids: Array = []
	for c in m.state.players[0].discard:
		discard_ids.append(c.instance_id)
	assert_bool(discard_ids.has(id0)).is_true()
	assert_bool(discard_ids.has(id1)).is_true()
