extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _spawn() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(999, "res://src/data/decks/strike.csv", "res://src/data/decks/raccoon.csv")
	return m

func test_played_minion_moves_from_hand_to_board() -> void:
	var m := _spawn()
	var legal: Array = m.engine.get_legal_actions()
	var play := legal.filter(func(a): return a.type == Enums.ActionType.PLAY_CARD)
	if play.is_empty():
		return
	var act = play[0]
	var iid: int = act.params["instance_id"]
	m.apply_action(act)
	assert_bool(m.hand_view.card_views.has(iid)).is_false()
	assert_bool(m.player_board.card_views.has(iid)).is_true()

func test_state_is_source_of_truth_after_apply() -> void:
	var m := _spawn()
	m.apply_action(Action.end_turn())
	assert_int(m.state.active_player).is_between(0, 1)