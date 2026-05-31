extends GdUnitTestSuite

func _pile() -> Control:
	var p: Control = load("res://src/ui/table/pile_view.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_count_badge_reflects_size() -> void:
	var p := _pile()
	p.set_count(17)
	assert_str(p.find_child("Count").text).is_equal("17")

func test_empty_pile_hides_back() -> void:
	var p := _pile()
	p.set_count(0)
	assert_bool(p.find_child("Back").visible).is_false()

func test_hover_scales_up_when_nonempty() -> void:
	var p := _pile()
	p.set_count(3)
	await get_tree().process_frame
	p._on_pile_mouse_entered()
	await get_tree().create_timer(0.25).timeout
	assert_float(p.scale.x).is_greater(1.0)

func test_hover_ignored_when_empty() -> void:
	var p := _pile()
	p.set_count(0)
	await get_tree().process_frame
	p._on_pile_mouse_entered()
	await get_tree().create_timer(0.25).timeout
	assert_float(p.scale.x).is_equal_approx(1.0, 0.001)

func test_exit_returns_to_rest() -> void:
	var p := _pile()
	p.set_count(3)
	await get_tree().process_frame
	p._on_pile_mouse_entered()
	await get_tree().create_timer(0.25).timeout
	p._on_pile_mouse_exited()
	await get_tree().create_timer(0.5).timeout
	assert_float(p.scale.x).is_equal_approx(1.0, 0.02)
