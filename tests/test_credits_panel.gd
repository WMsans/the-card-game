# tests/test_credits_panel.gd
extends GdUnitTestSuite

func _spawn() -> CreditsPanel:
	var p: CreditsPanel = load("res://src/ui/shell/credits_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_back_button_emits_back_pressed() -> void:
	var p := _spawn()
	var fired := [false]
	p.back_pressed.connect(func() -> void: fired[0] = true)
	p.get_node("%Back").pressed.emit()
	assert_bool(fired[0]).is_true()

func test_credits_label_contains_artists_from_file() -> void:
	var p := _spawn()
	var text: String = p.get_node("CreditsLabel").text
	assert_bool("Jacob Ho" in text).is_true()
	assert_bool("Ian Rodriguez" in text).is_true()
	assert_bool("Alexander Cortez" in text).is_true()
	assert_bool("Brandon Tsai" in text).is_true()
	assert_bool("Conner Wood" in text).is_true()

func test_credits_label_starts_below_viewport() -> void:
	var p := _spawn()
	var vp_height := p.get_viewport_rect().size.y
	assert_bool(p.get_node("CreditsLabel").position.y >= vp_height).is_true()
