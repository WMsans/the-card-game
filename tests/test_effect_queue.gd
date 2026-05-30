extends GdUnitTestSuite

func _eng() -> GameEngine:
	var state := GameState.new(1)
	return GameEngine.new(state)

func test_emit_publishes_to_bus_log() -> void:
	var eng := _eng()
	eng.emit(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": 0}))
	assert_int(eng.state.bus.log.size()).is_equal(1)
	assert_int(eng.state.bus.log[0].type).is_equal(Enums.EventType.TURN_STARTED)

func test_reentrant_emit_drains_in_order() -> void:
	var eng := _eng()
	var seen: Array = []
	eng.state.bus.subscribe(func(e: GameEvent):
		seen.append(e.type)
		if e.type == Enums.EventType.TURN_STARTED and seen.size() == 1:
			eng.emit(GameEvent.new(Enums.EventType.TURN_ENDED, {}))
	)
	eng.emit(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": 0}))
	assert_array(seen).is_equal([Enums.EventType.TURN_STARTED, Enums.EventType.TURN_ENDED])

# A throwaway script that counts reactions to CARD_DRAWN while on the board.
class CounterScript extends CardScript:
	var hits := 0
	func reacts_to() -> Array: return [Enums.EventType.CARD_DRAWN]
	func active_zones() -> Array: return [Enums.Zone.BOARD]
	func react(card, event, ctx) -> void: hits += 1

func test_board_card_reacts_to_event() -> void:
	var state := GameState.new(3)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var sc := CounterScript.new()
	var unit := state.make_instance(TestFactory.minion(1, 1, 1, 900))
	unit.card_script = sc
	unit.zone = Enums.Zone.BOARD
	state.players[0].board.append(unit)
	eng.emit(GameEvent.new(Enums.EventType.CARD_DRAWN, {"player": 0, "instance": 1}))
	assert_int(sc.hits).is_equal(1)

func test_card_off_its_active_zone_does_not_react() -> void:
	var state := GameState.new(3)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	var sc := CounterScript.new()
	var unit := state.make_instance(TestFactory.minion(1, 1, 1, 901))
	unit.card_script = sc
	unit.zone = Enums.Zone.HAND       # not BOARD
	state.players[0].hand.append(unit)
	eng.emit(GameEvent.new(Enums.EventType.CARD_DRAWN, {"player": 0, "instance": 1}))
	assert_int(sc.hits).is_equal(0)
