extends GdUnitTestSuite

func test_publish_appends_to_log() -> void:
	var bus := EventBus.new()
	bus.publish(GameEvent.new(Enums.EventType.TURN_STARTED, {"player": 0}))
	assert_array(bus.log).has_size(1)
	assert_int(bus.log[0].type).is_equal(Enums.EventType.TURN_STARTED)

func test_subscribers_are_notified() -> void:
	var bus := EventBus.new()
	var seen := []
	bus.subscribe(func(e: GameEvent): seen.append(e.type))
	bus.publish(GameEvent.new(Enums.EventType.CARD_DRAWN))
	assert_array(seen).is_equal([Enums.EventType.CARD_DRAWN])

func test_events_of_type_filters() -> void:
	var bus := EventBus.new()
	bus.publish(GameEvent.new(Enums.EventType.CARD_DRAWN))
	bus.publish(GameEvent.new(Enums.EventType.TURN_ENDED))
	bus.publish(GameEvent.new(Enums.EventType.CARD_DRAWN))
	assert_array(bus.events_of_type(Enums.EventType.CARD_DRAWN)).has_size(2)
