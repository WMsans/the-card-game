extends GdUnitTestSuite

func test_unknown_card_resolves_to_default() -> void:
	var s := CardScriptRegistry.get_script_for("nope", 999)
	assert_object(s).is_not_null()
	assert_bool(s is DefaultCard).is_true()
