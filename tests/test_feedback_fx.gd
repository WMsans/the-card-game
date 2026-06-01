extends GdUnitTestSuite

func test_next_speed_ramps_up_on_quick_chain() -> void:
	assert_float(FeedbackFx.next_speed(1.0, 0.1)).is_equal_approx(1.35, 0.001)

func test_next_speed_caps_at_max() -> void:
	assert_float(FeedbackFx.next_speed(2.4, 0.1)).is_equal_approx(2.5, 0.001)

func test_next_speed_resets_after_a_lull() -> void:
	assert_float(FeedbackFx.next_speed(2.0, 1.0)).is_equal_approx(1.0, 0.001)

func test_bump_pile_runs_without_error_and_restores_scale() -> void:
	var pile := Control.new()
	add_child(pile)
	auto_free(pile)
	pile.scale = Vector2.ONE
	FeedbackFx.bump_pile(pile, 1.0)
	await get_tree().create_timer(0.3).timeout
	assert_vector(pile.scale).is_equal_approx(Vector2.ONE, Vector2(0.02, 0.02))
