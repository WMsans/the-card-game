extends GdUnitTestSuite

func _spawn() -> Node:
	var n := Node2D.new()
	n.set_script(load("res://src/ui/table/opponent_hand.gd"))
	add_child(n)
	auto_free(n)
	return n

func test_renders_n_face_down_backs() -> void:
	var oh := _spawn()
	oh.set_count(4)
	assert_int(oh.get_child_count()).is_equal(4)
