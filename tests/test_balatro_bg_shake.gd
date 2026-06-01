# tests/test_balatro_bg_shake.gd
extends GdUnitTestSuite

func _spawn() -> BalatroBg:
	var bg: BalatroBg = load("res://src/ui/match/balatro_bg.tscn").instantiate()
	add_child(bg)
	auto_free(bg)
	return bg

func test_trauma_starts_at_zero() -> void:
	var bg := _spawn()
	assert_float(bg.get_trauma()).is_equal_approx(0.0, 0.0001)

func test_add_trauma_is_clamped_to_one() -> void:
	var bg := _spawn()
	bg.add_trauma(5.0)
	assert_float(bg.get_trauma()).is_equal_approx(1.0, 0.0001)

func test_shake_emits_nonzero_foreground_offset() -> void:
	var bg := _spawn()
	bg.add_trauma(1.0)
	var captured := [Vector2.ZERO]
	bg.foreground_offset.connect(func(o: Vector2) -> void: captured[0] = o)
	bg._process(0.016)
	assert_vector(captured[0]).is_not_equal(Vector2.ZERO)

func test_trauma_decays_to_zero_over_time() -> void:
	var bg := _spawn()
	bg.add_trauma(1.0)
	for i in range(240):
		bg._process(0.016)
	assert_float(bg.get_trauma()).is_equal_approx(0.0, 0.0001)
