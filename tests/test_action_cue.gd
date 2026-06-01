extends GdUnitTestSuite

func _ev(type: int, data: Dictionary) -> GameEvent:
	return GameEvent.new(type, data)

func test_minion_played_makes_played_cue_on_card() -> void:
	var ds := ActionCue.descriptors([_ev(Enums.EventType.CARD_PLAYED,
		{"player": 0, "instance": 7, "card_type": Enums.CardType.MINION})])
	assert_int(ds.size()).is_equal(1)
	assert_str(ds[0]["label"]).is_equal("PLAYED")
	assert_int(ds[0]["target_id"]).is_equal(7)
	assert_str(ds[0]["anchor"]).is_equal("card")

func test_spell_and_trap_played_make_no_generic_cue() -> void:
	var ds := ActionCue.descriptors([
		_ev(Enums.EventType.CARD_PLAYED, {"player": 0, "instance": 8, "card_type": Enums.CardType.SPELL}),
		_ev(Enums.EventType.CARD_PLAYED, {"player": 0, "instance": 9, "card_type": Enums.CardType.TRAP}),
	])
	assert_int(ds.size()).is_equal(0)

func test_request_met_makes_cue_on_card() -> void:
	var ds := ActionCue.descriptors([_ev(Enums.EventType.REQUEST_MET, {"player": 0, "instance": 5})])
	assert_str(ds[0]["label"]).is_equal("REQUEST MET")
	assert_int(ds[0]["target_id"]).is_equal(5)

func test_harmonize_makes_board_anchored_cue() -> void:
	var ds := ActionCue.descriptors([_ev(Enums.EventType.HARMONIZE, {"player": 1})])
	assert_str(ds[0]["label"]).is_equal("HARMONIZE")
	assert_str(ds[0]["anchor"]).is_equal("board")
	assert_int(ds[0]["player"]).is_equal(1)

func test_rummage_makes_discard_anchored_cue_with_count() -> void:
	var ds := ActionCue.descriptors([_ev(Enums.EventType.RUMMAGE_PERFORMED, {"player": 0, "count": 3})])
	assert_str(ds[0]["label"]).is_equal("RUMMAGE x3")
	assert_str(ds[0]["anchor"]).is_equal("discard")

func test_trashed_makes_cue_on_unit() -> void:
	var ds := ActionCue.descriptors([_ev(Enums.EventType.UNIT_TRASHED, {"owner": 0, "instance": 11})])
	assert_str(ds[0]["label"]).is_equal("TRASHED")
	assert_int(ds[0]["target_id"]).is_equal(11)

func test_passive_movement_events_make_no_cue() -> void:
	var ds := ActionCue.descriptors([
		_ev(Enums.EventType.CARD_DRAWN, {"player": 0, "instance": 1}),
		_ev(Enums.EventType.CARD_DISCARDED, {"player": 0, "instance": 2}),
		_ev(Enums.EventType.CARD_RUMMAGED, {"player": 0, "instance": 3}),
	])
	assert_int(ds.size()).is_equal(0)

const MATCH := "res://src/ui/match/match.tscn"
const STRIKE := "res://src/data/decks/strike.csv"

func _match() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, STRIKE, STRIKE)
	await get_tree().create_timer(0.35).timeout
	return m

func test_play_spawns_a_label_for_harmonize() -> void:
	var m := await _match()
	var fx_before: int = m.get_node("FxLayer").get_child_count()
	var cue := ActionCue.new()
	await cue.play(m, [GameEvent.new(Enums.EventType.HARMONIZE, {"player": 0})])
	assert_int(m.get_node("FxLayer").get_child_count()).is_greater(fx_before)

func test_play_with_no_cue_events_is_noop() -> void:
	var m := await _match()
	var fx_before: int = m.get_node("FxLayer").get_child_count()
	var cue := ActionCue.new()
	await cue.play(m, [GameEvent.new(Enums.EventType.CARD_DRAWN, {"player": 0, "instance": 1})])
	assert_int(m.get_node("FxLayer").get_child_count()).is_equal(fx_before)
