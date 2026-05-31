# tests/test_foundation_cost.gd
extends CardTestBase

class CheapWhenBoarded extends CardScript:
	func cost_modifier(_card: CardInstance, ctx) -> int:
		return -ctx.board(ctx.me()).size()

func test_effective_cost_applies_script_modifier_and_clamps() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var def := TestFactory.minion(10, 1, 16, 8)
	var card := eng.state.make_instance(def)
	card.card_script = CheapWhenBoarded.new()
	# 3 dummy minions on board -> cost 10 - 3 = 7
	for i in range(3):
		place_on_board(eng, me, TestFactory.minion(1, 1, 1, 200 + i))
	assert_int(eng.effective_cost(card, me)).is_equal(7)

func test_effective_cost_never_negative() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var def := TestFactory.minion(1, 1, 1, 9)
	var card := eng.state.make_instance(def)
	card.card_script = CheapWhenBoarded.new()
	for i in range(5):
		place_on_board(eng, me, TestFactory.minion(1, 1, 1, 300 + i))
	assert_int(eng.effective_cost(card, me)).is_equal(0)
