extends GdUnitTestSuite

func _spawn() -> Control:
	var m: Control = load("res://src/ui/match/match.tscn").instantiate()
	add_child(m)
	auto_free(m)
	return m

func test_match_instantiates_without_a_background() -> void:
	var m := _spawn()
	assert_object(m).is_not_null()
	assert_bool(m.has_node("BalatroBg")).is_false()

func test_attach_background_wires_foreground_parallax() -> void:
	var m := _spawn()
	var bg: BalatroBg = load("res://src/ui/match/balatro_bg.tscn").instantiate()
	add_child(bg)
	auto_free(bg)
	m.attach_background(bg)
	var table: Control = m.get_node("Table")
	bg.foreground_offset.emit(Vector2(7, 9))
	assert_vector(table.position).is_equal(Vector2(7, 9))
