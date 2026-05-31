# tests/test_foundation_basics.gd
extends GdUnitTestSuite

func test_new_event_types_exist_and_are_distinct() -> void:
	var types := [
		Enums.EventType.CARD_RUMMAGED, Enums.EventType.RUMMAGE_PERFORMED,
		Enums.EventType.HARMONIZE, Enums.EventType.UNIT_TRASHED,
	]
	# all distinct
	assert_int(types.size()).is_equal(4)
	for i in range(types.size()):
		for j in range(i + 1, types.size()):
			assert_bool(types[i] == types[j]).is_false()

func test_rummages_made_counter_starts_zero() -> void:
	var ps := PlayerState.new()
	assert_int(ps.turn_counters["rummages_made"]).is_equal(0)

func test_default_hooks_return_neutral_values() -> void:
	var s := CardScript.new()
	assert_int(s.cost_modifier(null, null)).is_equal(0)
	assert_int(s.rummage_bonus(null, null)).is_equal(0)
	assert_bool(s.is_clef()).is_false()
	assert_bool(s.is_note()).is_false()
	assert_bool(s.can_intercept_deck_damage(null, 0, 0, null)).is_false()
	assert_int(s.deck_damage_on_fire(null, 0, 5, null)).is_equal(5)
	assert_bool(s.can_intercept_kill(null, null, "battle", null)).is_false()
	assert_bool(s.kill_on_fire(null, null, null)).is_false()
	assert_str(s.trash_replacement_for(null, null, null)).is_equal("")

func test_untap_and_set_taunt_verbs() -> void:
	var state := GameState.new(1)
	var eng := GameEngine.new(state)
	var ctx := EffectContext.new(eng, 0)
	var u := CardInstance.new(1, TestFactory.minion(1, 1, 1, 1))
	u.tapped = true
	ctx.untap(u)
	assert_bool(u.tapped).is_false()
	ctx.set_taunt(u)
	assert_bool(u.vars.get("taunt", false)).is_true()
