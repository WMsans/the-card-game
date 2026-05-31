# tests/test_foundation_rummage.gd
extends CardTestBase

class RummageBonusUnit extends CardScript:
	func rummage_bonus(_card: CardInstance, _ctx) -> int: return 1

func _seed_discard(eng: GameEngine, p: int, n: int) -> Array:
	var out: Array = []
	for i in range(n):
		var c := eng.state.make_instance(TestFactory.minion(1, 1, 1, 500 + i))
		c.zone = Enums.Zone.DISCARD
		eng.state.players[p].discard.append(c)
		out.append(c)
	return out

func test_rummage_draws_from_bottom_front_of_discard() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var disc := _seed_discard(eng, me, 3)  # disc[0] is the bottom
	EffectContext.new(eng, me).rummage(1)
	assert_bool(eng.state.players[me].hand.has(disc[0])).is_true()
	assert_int(eng.state.players[me].discard.size()).is_equal(2)

func test_rummage_increments_counter_and_emits_instance_event() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	_seed_discard(eng, me, 3)
	var from := eng.state.bus.log.size()
	EffectContext.new(eng, me).rummage(2)
	assert_int(eng.state.players[me].turn_counters["rummages_made"]).is_equal(1)
	var perf := eng.state.bus.log.slice(from).filter(
		func(e): return e.type == Enums.EventType.RUMMAGE_PERFORMED)
	assert_int(perf.size()).is_equal(1)
	assert_int(perf[0].data["count"]).is_equal(2)

func test_rummage_bonus_from_board_adds_cards() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	_seed_discard(eng, me, 5)
	var coyote := place_on_board(eng, me, TestFactory.minion(4, 6, 3, 8))
	coyote.card_script = RummageBonusUnit.new()
	EffectContext.new(eng, me).rummage(2)  # 2 + 1 bonus = 3
	assert_bool(eng.state.players[me].hand.size() >= 3).is_true()
	assert_int(eng.state.players[me].discard.size()).is_equal(2)
