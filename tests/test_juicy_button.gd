extends GdUnitTestSuite

func _btn() -> Button:
	var b := Button.new()
	b.size = Vector2(120, 40)
	add_child(b)
	auto_free(b)
	return b

func test_apply_recenters_pivot_and_connects_signals() -> void:
	var b := _btn()
	JuicyButton.apply(b)
	assert_vector(b.pivot_offset).is_equal(Vector2(60, 20))
	assert_int(b.mouse_entered.get_connections().size()).is_greater(0)
	assert_int(b.button_down.get_connections().size()).is_greater(0)

func test_disabled_button_does_not_scale_on_hover() -> void:
	var b := _btn()
	b.disabled = true
	JuicyButton.apply(b)
	b.mouse_entered.emit()
	assert_vector(b.scale).is_equal(Vector2.ONE)