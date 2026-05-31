extends GdUnitTestSuite

func _ev(type: int, data: Dictionary) -> GameEvent:
	return GameEvent.new(type, data)

func test_has_attack_true_when_unit_attacked_present() -> void:
	var events := [_ev(Enums.EventType.UNIT_ATTACKED, {"attacker": 1, "player": 0, "target_unit": 2})]
	assert_bool(CombatDirector.has_attack(events)).is_true()

func test_has_attack_false_for_non_attack_events() -> void:
	var events := [_ev(Enums.EventType.CARD_DRAWN, {"player": 0, "instance": 9})]
	assert_bool(CombatDirector.has_attack(events)).is_false()

func test_parse_cluster_unit_attack() -> void:
	var events := [
		_ev(Enums.EventType.UNIT_ATTACKED, {"attacker": 5, "player": 0, "target_unit": 9}),
		_ev(Enums.EventType.UNIT_DAMAGED, {"target": 9, "amount": 3}),
		_ev(Enums.EventType.UNIT_DAMAGED, {"target": 5, "amount": 1}),
		_ev(Enums.EventType.UNIT_DIED, {"owner": 1, "instance": 9}),
	]
	var c := CombatDirector.parse_cluster(events)
	assert_int(c["attacker"]).is_equal(5)
	assert_int(c["target_unit"]).is_equal(9)
	assert_int(c["player"]).is_equal(0)
	assert_int(c["damaged"].size()).is_equal(2)
	assert_int(c["damaged"][0]["id"]).is_equal(9)
	assert_int(c["damaged"][0]["amount"]).is_equal(3)
	assert_array(c["died"]).contains([9])

func test_parse_cluster_deck_attack_captures_deck_amount() -> void:
	var events := [
		_ev(Enums.EventType.UNIT_ATTACKED, {"attacker": 4, "player": 0, "target_unit": -1}),
		_ev(Enums.EventType.DECK_DAMAGED, {"player": 1, "amount": 2}),
	]
	var c := CombatDirector.parse_cluster(events)
	assert_int(c["target_unit"]).is_equal(-1)
	assert_int(c["deck_amount"]).is_equal(2)

func test_next_speed_ramps_up_on_quick_chain() -> void:
	assert_float(CombatDirector.next_speed(1.0, 0.1)).is_equal_approx(1.35, 0.001)

func test_next_speed_caps_at_max() -> void:
	assert_float(CombatDirector.next_speed(2.4, 0.1)).is_equal_approx(2.5, 0.001)

func test_next_speed_resets_after_a_lull() -> void:
	assert_float(CombatDirector.next_speed(2.0, 1.0)).is_equal_approx(1.0, 0.001)

func test_reset_ramp_sets_speed_to_one() -> void:
	var d := CombatDirector.new()
	d.anim_speed = 2.2
	d.reset_ramp()
	assert_float(d.anim_speed).is_equal_approx(1.0, 0.001)

const MATCH := "res://src/ui/match/match.tscn"

func _spawn_match() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func _put_unit_on_player_board(m: Node, iid: int) -> CardView:
	var def := CardDefinition.new()
	def.name = "Tester"
	def.type = Enums.CardType.MINION
	def.base_damage = 2
	def.base_health = 3
	var inst := CardInstance.new(iid, def)
	inst.current_damage = 2
	inst.current_health = 3
	m.player_board.render([inst], 0)
	await get_tree().create_timer(0.35).timeout
	return m.player_board.card_views[iid]

func test_deck_attack_returns_attacker_home_and_spawns_number() -> void:
	var m := _spawn_match()
	var cv := await _put_unit_on_player_board(m, 42)
	var rest := cv._rest_position
	var fx_before: int = m.get_node("FxLayer").get_child_count()
	var events := [
		GameEvent.new(Enums.EventType.UNIT_ATTACKED, {"attacker": 42, "player": 0, "target_unit": -1}),
		GameEvent.new(Enums.EventType.DECK_DAMAGED, {"player": 1, "amount": 2}),
	]
	var director := CombatDirector.new()
	await director.play(events, m)
	assert_vector(cv.position).is_equal_approx(rest, Vector2(3, 3))
	assert_int(m.get_node("FxLayer").get_child_count()).is_greater(fx_before)

func test_play_no_attack_is_a_noop() -> void:
	var m := _spawn_match()
	var director := CombatDirector.new()
	await director.play([GameEvent.new(Enums.EventType.CARD_DRAWN, {"player": 0, "instance": 1})], m)
	assert_bool(true).is_true()
