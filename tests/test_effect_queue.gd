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
