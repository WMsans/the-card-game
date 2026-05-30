extends GdUnitTestSuite

func _overlay() -> DropZoneOverlay:
	var o := DropZoneOverlay.new()
	o.size = Vector2(1920, 1080)
	add_child(o)
	auto_free(o)
	return o

func test_hidden_by_default() -> void:
	assert_bool(_overlay().is_hovering_zone()).is_false()

func test_hit_test_inside_and_outside() -> void:
	var o := _overlay()
	o.show_zones([Rect2(0, 0, 100, 100)])
	o.set_hover(Vector2(50, 50), DropZoneOverlay.ZoneState.ACCEPTABLE)
	assert_bool(o.is_hovering_zone()).is_true()
	o.set_hover(Vector2(500, 500), DropZoneOverlay.ZoneState.ACCEPTABLE)
	assert_bool(o.is_hovering_zone()).is_false()

func test_clear_resets() -> void:
	var o := _overlay()
	o.show_zones([Rect2(0, 0, 100, 100)])
	o.set_hover(Vector2(50, 50), DropZoneOverlay.ZoneState.ACCEPTABLE)
	o.clear()
	assert_bool(o.is_hovering_zone()).is_false()