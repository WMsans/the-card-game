extends GdUnitTestSuite

func _match() -> Node:
	var m = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	return m

func test_human_intercept_opens_reveal_overlay() -> void:
	var m := _match()
	m.start_game(7, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	var trap: CardInstance = m.state.make_instance(CardDatabase.load_deck("res://src/data/decks/strike.csv", "strike")[18])
	m.state.pending_choice = PendingChoice.new("intercept", 0, {
		"op": "deck_damage", "trap_id": trap.instance_id, "player": 0, "amount": 6,
		"spec": ChoiceSpec.intercept(trap, "Your Deck will take 6 damage", ["Fire", "Decline"]),
		"ui_shape": "intercept",
	})
	m._route_pending_choice()
	assert_bool(m._trap_reveal.visible).is_true()
	assert_bool(m._trap_reveal.buttons_visible()).is_true()
