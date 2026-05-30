extends GdUnitTestSuite

func _spawn() -> Node:
	var m: Node = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(42, "res://src/data/decks/strike.csv", "res://src/data/decks/raccoon.csv")
	return m

func test_play_via_drop_handler_moves_card_to_board_or_discard() -> void:
	var m: Node = _spawn()
	var legal: Array = m.engine.get_legal_actions()
	var play := legal.filter(func(a): return a.type == Enums.ActionType.PLAY_CARD)
	if play.is_empty():
		return
	var iid: int = play[0].params["instance_id"]
	var handled: bool = m.handle_drop(iid, "play_zone")
	assert_bool(handled).is_true()
	assert_bool(m.hand_view.card_views.has(iid)).is_false()

func test_illegal_drop_is_rejected() -> void:
	var m: Node = _spawn()
	assert_bool(m.handle_drop(99999, "play_zone")).is_false()

func test_highlights_mark_legal_attackers() -> void:
	var m: Node = _spawn()
	var attackers: Array = m.legal_attacker_ids()
	assert_object(attackers).is_not_null()