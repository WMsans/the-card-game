extends GdUnitTestSuite

func test_core_colors_are_defined() -> void:
	assert_int(typeof(UiPalette.BTN_NORMAL)).is_equal(TYPE_COLOR)
	assert_int(typeof(UiPalette.HL_PLAYABLE)).is_equal(TYPE_COLOR)
	assert_int(typeof(UiPalette.PIP_COST)).is_equal(TYPE_COLOR)

func test_drag_zone_colors_are_translucent() -> void:
	assert_float(UiPalette.ZONE_ACCEPTABLE.a).is_less(1.0)
	assert_float(UiPalette.ZONE_UNAFFORDABLE.a).is_less(1.0)
	assert_float(UiPalette.ZONE_NEUTRAL.a).is_less(1.0)