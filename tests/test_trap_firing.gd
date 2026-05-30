extends GdUnitTestSuite

class KillerTrap extends CardScript:
	func reacts_to() -> Array: return [Enums.EventType.UNIT_ATTACKED]
	func active_zones() -> Array: return [Enums.Zone.TRAP_SET]
	func react(card, event, ctx) -> void:
		ctx.fire_trap(card)

func test_fire_trap_moves_to_discard_and_emits() -> void:
	var state := GameState.new(21)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var trap := state.make_instance(TestFactory.trap(2, 600))
	trap.card_script = KillerTrap.new()
	trap.zone = Enums.Zone.TRAP_SET
	state.players[1].set_traps.append(trap)
	eng.emit(GameEvent.new(Enums.EventType.UNIT_ATTACKED, {"attacker": 1, "player": 0}))
	assert_bool(state.players[1].set_traps.has(trap)).is_false()
	assert_bool(state.players[1].discard.has(trap)).is_true()
	assert_int(state.bus.events_of_type(Enums.EventType.TRAP_FIRED).size()).is_equal(1)
