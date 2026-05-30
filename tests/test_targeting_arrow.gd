extends GdUnitTestSuite

func _spawn() -> Node2D:
	var n := Node2D.new()
	n.set_script(load("res://src/ui/table/targeting_arrow.gd"))
	add_child(n)
	auto_free(n)
	return n

func test_inactive_by_default() -> void:
	assert_bool(_spawn().active).is_false()

func test_begin_sets_active_and_start() -> void:
	var a := _spawn()
	a.begin(Vector2(100, 200))
	assert_bool(a.active).is_true()
	assert_vector(a.start).is_equal(Vector2(100, 200))

func test_bezier_point_endpoints() -> void:
	var a := _spawn()
	a.begin(Vector2(0, 0))
	a.point_at(Vector2(100, 0))
	assert_vector(a._curve_point(0.0)).is_equal(Vector2(0, 0))
	assert_vector(a._curve_point(1.0)).is_equal(Vector2(100, 0))