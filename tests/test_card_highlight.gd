extends GdUnitTestSuite

func _hl() -> CardHighlight:
	var h := CardHighlight.new()
	h.size = Vector2(350, 490)
	add_child(h)
	auto_free(h)
	return h

func test_starts_hidden() -> void:
	assert_bool(_hl().visible).is_false()

func test_set_state_toggles_visibility() -> void:
	var h := _hl()
	h.set_state(CardHighlight.State.PLAYABLE)
	assert_bool(h.visible).is_true()
	h.set_state(CardHighlight.State.NONE)
	assert_bool(h.visible).is_false()

func test_set_state_selects_color() -> void:
	var h := _hl()
	h.set_state(CardHighlight.State.SELECTED)
	assert_object(h.current_color()).is_equal(UiPalette.HL_SELECTED)