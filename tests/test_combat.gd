extends GdUnitTestSuite

func _unit(dmg: int, hp: int) -> CardInstance:
	return CardInstance.new(1, TestFactory.minion(1, dmg, hp))

func test_lethal_is_damage_equal_to_health() -> void:
	var atk := _unit(3, 2)
	var def := _unit(1, 3)
	var r := Combat.compute(atk, def)
	assert_bool(r["def_dies"]).is_true()
	assert_bool(r["atk_dies"]).is_false()
	assert_int(r["dmg_to_atk"]).is_equal(1)

func test_below_health_survives() -> void:
	var atk := _unit(2, 5)
	var def := _unit(1, 3)
	var r := Combat.compute(atk, def)
	assert_bool(r["def_dies"]).is_false()

func test_simultaneous_trade() -> void:
	var atk := _unit(3, 3)
	var def := _unit(3, 3)
	var r := Combat.compute(atk, def)
	assert_bool(r["def_dies"]).is_true()
	assert_bool(r["atk_dies"]).is_true()
