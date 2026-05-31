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
