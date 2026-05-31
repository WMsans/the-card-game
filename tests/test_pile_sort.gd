extends GdUnitTestSuite

func _inst(id: int, type: int, name: String) -> CardInstance:
	var d := CardDefinition.new()
	d.type = type
	d.name = name
	return CardInstance.new(id, d)

func _names(cards: Array[CardInstance]) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.definition.name)
	return out

func test_sorts_by_type_enum_order_then_name() -> void:
	var cards: Array[CardInstance] = [
		_inst(1, Enums.CardType.SPELL, "Zap"),
		_inst(2, Enums.CardType.MINION, "Badger"),
		_inst(3, Enums.CardType.LEADER, "Chief"),
		_inst(4, Enums.CardType.MINION, "Ant"),
		_inst(5, Enums.CardType.TRAP, "Snare"),
	]
	var out := PileSort.sorted(cards)
	# Minion(Ant, Badger), Spell(Zap), Trap(Snare), Leader(Chief)
	assert_array(_names(out)).is_equal(["Ant", "Badger", "Zap", "Snare", "Chief"])

func test_name_sort_is_case_insensitive() -> void:
	var cards: Array[CardInstance] = [
		_inst(1, Enums.CardType.MINION, "banana"),
		_inst(2, Enums.CardType.MINION, "Apple"),
		_inst(3, Enums.CardType.MINION, "cherry"),
	]
	assert_array(_names(PileSort.sorted(cards))).is_equal(["Apple", "banana", "cherry"])

func test_stable_for_equal_keys() -> void:
	# Same type and name: original input order (by id 10, then 11) is preserved.
	var first := _inst(10, Enums.CardType.MINION, "Twin")
	var second := _inst(11, Enums.CardType.MINION, "Twin")
	var cards: Array[CardInstance] = [first, second]
	var out := PileSort.sorted(cards)
	assert_int(out[0].instance_id).is_equal(10)
	assert_int(out[1].instance_id).is_equal(11)

func test_does_not_mutate_input() -> void:
	var cards: Array[CardInstance] = [
		_inst(1, Enums.CardType.SPELL, "Zap"),
		_inst(2, Enums.CardType.MINION, "Ant"),
	]
	var before := _names(cards)
	PileSort.sorted(cards)
	assert_array(_names(cards)).is_equal(before)

func test_empty_and_single() -> void:
	var empty: Array[CardInstance] = []
	assert_int(PileSort.sorted(empty).size()).is_equal(0)
	var one: Array[CardInstance] = [_inst(1, Enums.CardType.TRAP, "Solo")]
	assert_array(_names(PileSort.sorted(one))).is_equal(["Solo"])
