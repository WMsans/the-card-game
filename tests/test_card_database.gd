extends GdUnitTestSuite

func test_strike_deck_has_one_leader_and_twenty_cards() -> void:
	var defs := CardDatabase.load_deck("res://src/data/decks/strike.csv", "Strike")
	var leaders := defs.filter(func(d): return d.type == Enums.CardType.LEADER)
	var non_leaders := defs.filter(func(d): return d.type != Enums.CardType.LEADER)
	assert_array(leaders).has_size(1)
	assert_array(non_leaders).has_size(20)

func test_leader_cost_and_discard_cost_parsed() -> void:
	var defs := CardDatabase.load_deck("res://src/data/decks/strike.csv", "Strike")
	var bjorn: CardDefinition = defs.filter(func(d): return d.type == Enums.CardType.LEADER)[0]
	assert_int(bjorn.ticket_cost).is_equal(7)
	assert_int(bjorn.alt_discard_cost).is_equal(4)
	assert_int(bjorn.base_damage).is_equal(2)
	assert_int(bjorn.base_health).is_equal(10)
	assert_str(bjorn.deck_color).is_equal("Strike")

func test_parenthetical_stat_takes_base_value() -> void:
	var defs := CardDatabase.load_deck("res://src/data/decks/audio.csv", "Audio")
	var quarter: CardDefinition = defs.filter(func(d): return d.name == "Quarter Note")[0]
	assert_int(quarter.base_damage).is_equal(1)

func test_spell_has_zero_stats() -> void:
	var defs := CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "Raccoon")
	var spell: CardDefinition = defs.filter(func(d): return d.type == Enums.CardType.SPELL)[0]
	assert_int(spell.base_damage).is_equal(0)
	assert_int(spell.base_health).is_equal(0)

func test_all_four_decks_load_without_error() -> void:
	for path in ["strike", "raccoon", "writing", "audio"]:
		var defs := CardDatabase.load_deck("res://src/data/decks/%s.csv" % path, path)
		assert_array(defs).is_not_empty()
