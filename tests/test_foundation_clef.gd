# tests/test_foundation_clef.gd
extends CardTestBase

class ClefStub extends CardScript:
	func is_clef() -> bool: return true

func _can_play(eng: GameEngine, iid: int) -> bool:
	for a in eng.get_legal_actions():
		if a.type == Enums.ActionType.PLAY_CARD and a.params["instance_id"] == iid:
			return true
	return false

func test_second_clef_not_playable_while_one_on_board() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.tickets_total = 20
	var on_board := place_on_board(eng, me, TestFactory.minion(5, 0, 5, 12))
	on_board.card_script = ClefStub.new()
	var in_hand := eng.state.make_instance(TestFactory.minion(5, 0, 5, 13))
	in_hand.card_script = ClefStub.new()
	in_hand.zone = Enums.Zone.HAND
	ps.hand.append(in_hand)
	assert_bool(_can_play(eng, in_hand.instance_id)).is_false()

func test_clef_playable_when_none_on_board() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var ps := eng.state.players[me]
	ps.tickets_total = 20
	var in_hand := eng.state.make_instance(TestFactory.minion(5, 0, 5, 13))
	in_hand.card_script = ClefStub.new()
	in_hand.zone = Enums.Zone.HAND
	ps.hand.append(in_hand)
	assert_bool(_can_play(eng, in_hand.instance_id)).is_true()
