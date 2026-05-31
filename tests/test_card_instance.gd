extends GdUnitTestSuite

func _make_def() -> CardDefinition:
	var d := CardDefinition.new()
	d.type = Enums.CardType.MINION
	d.base_damage = 3
	d.base_health = 2
	return d

func test_instance_copies_base_stats() -> void:
	var inst := CardInstance.new(7, _make_def())
	assert_int(inst.instance_id).is_equal(7)
	assert_int(inst.current_damage).is_equal(3)
	assert_int(inst.current_health).is_equal(2)
	assert_bool(inst.tapped).is_false()

func test_reset_stats_restores_base() -> void:
	var inst := CardInstance.new(1, _make_def())
	inst.current_health = 0
	inst.reset_stats()
	assert_int(inst.current_health).is_equal(2)

func test_is_unit() -> void:
	var inst := CardInstance.new(1, _make_def())
	assert_bool(inst.is_unit()).is_true()

func test_instance_has_vars_and_default_script() -> void:
	var d := CardDefinition.new()
	d.deck_color = "Test"
	d.id = 1
	var ci := CardInstance.new(7, d)
	assert_object(ci.vars).is_not_null()
	assert_int(ci.vars.size()).is_equal(0)
	assert_object(ci.card_script).is_null()   # raw CardInstance.new does not resolve script
