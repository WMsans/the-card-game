extends GdUnitTestSuite

func test_unit_damaged_event_spawns_a_damage_number() -> void:
	var m: Control = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, "res://src/data/decks/strike.csv", "res://src/data/decks/raccoon.csv")
	var fx_before: int = m.get_node("FxLayer").get_child_count()
	var evt := GameEvent.new(Enums.EventType.UNIT_DAMAGED, {"target": 1, "amount": 3})
	m._play_flourishes([evt])
	assert_int(m.get_node("FxLayer").get_child_count()).is_greater(fx_before)

func _spawn() -> Node:
	var m: Node = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, "res://src/data/decks/strike.csv", "res://src/data/decks/raccoon.csv")
	return m

func test_attack_flag_suppresses_unit_damage_number() -> void:
	var m := _spawn()
	var before := m.get_node("FxLayer").get_child_count()
	Flourishes.play(m, [GameEvent.new(Enums.EventType.UNIT_DAMAGED, {"target": -1, "amount": 3})], true)
	assert_int(m.get_node("FxLayer").get_child_count()).is_equal(before)

func test_deck_mill_still_fires_during_attack() -> void:
	var m := _spawn()
	var before := m.get_node("FxLayer").get_child_count()
	Flourishes.play(m, [GameEvent.new(Enums.EventType.DECK_DAMAGED, {"player": 0, "amount": 2})], true)
	assert_int(m.get_node("FxLayer").get_child_count()).is_greater(before)