extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _a_card() -> CardView:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(3, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	await get_tree().create_timer(0.35).timeout
	return m.hand_view.card_views.values()[0]

func test_windup_lands_at_target_and_scales_up() -> void:
	var cv := await _a_card()
	var base := cv.base_scale
	var tw := CardJuice.windup(cv, Vector2(400, 800))
	await tw.finished
	assert_vector(cv.position).is_equal_approx(Vector2(400, 800), Vector2(1.5, 1.5))
	assert_float(cv.scale.x).is_equal_approx(base * 1.08, 0.02)

func test_lunge_reaches_target() -> void:
	var cv := await _a_card()
	var tw := CardJuice.lunge(cv, Vector2(1200, 300))
	await tw.finished
	assert_vector(cv.position).is_equal_approx(Vector2(1200, 300), Vector2(2, 2))

func test_recoil_returns_to_rest_pos_rot_and_base_scale() -> void:
	var cv := await _a_card()
	var base := cv.base_scale
	var tw := CardJuice.recoil(cv, Vector2(700, 850), 0.1)
	await tw.finished
	assert_vector(cv.position).is_equal_approx(Vector2(700, 850), Vector2(2, 2))
	assert_float(cv.rotation).is_equal_approx(0.1, 0.02)
	assert_float(cv.scale.x).is_equal_approx(base, 0.02)

func test_squash_returns_to_base_scale() -> void:
	var cv := await _a_card()
	var base := cv.base_scale
	var tw := CardJuice.squash(cv)
	await tw.finished
	assert_float(cv.scale.x).is_equal_approx(base, 0.02)

func test_pop_ends_at_base_scale_and_white_modulate() -> void:
	var cv := await _a_card()
	var base := cv.base_scale
	var tw := CardJuice.pop(cv)
	await tw.finished
	assert_float(cv.scale.x).is_equal_approx(base, 0.03)
	assert_float(cv.modulate.r).is_equal_approx(1.0, 0.02)

func test_speed_shortens_duration() -> void:
	var cv := await _a_card()
	var t0 := Time.get_ticks_msec()
	await CardJuice.recoil(cv, cv.position, cv.rotation, 1.0).finished
	var slow := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	await CardJuice.recoil(cv, cv.position, cv.rotation, 2.5).finished
	var fast := Time.get_ticks_msec() - t0
	assert_int(fast).is_less(slow)

func _card() -> CardView:
	var cv: CardView = load("res://src/ui/card/card_view.tscn").instantiate()
	add_child(cv)
	auto_free(cv)
	return cv

func test_spring_wiggle_returns_to_upright() -> void:
	var cv := _card()
	cv.rotation = 0.3
	var tw := CardJuice.spring_wiggle(cv, 10.0)
	await get_tree().create_timer(0.14).timeout
	assert_float(cv.rotation).is_greater(0.3)
	await tw.finished
	assert_float(cv.rotation).is_equal_approx(0.3, 0.01)

func _panel() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(200, 200)
	c.size = Vector2(200, 200)
	add_child(c)
	auto_free(c)
	return c

func test_popup_in_ends_at_full_scale_and_alpha() -> void:
	var p := _panel()
	await CardJuice.popup_in(p).finished
	assert_vector(p.scale).is_equal_approx(Vector2.ONE, Vector2(0.01, 0.01))
	assert_float(p.modulate.a).is_equal_approx(1.0, 0.01)

func test_popup_out_ends_hidden() -> void:
	var p := _panel()
	await CardJuice.popup_out(p).finished
	assert_vector(p.scale).is_equal_approx(Vector2(0.9, 0.9), Vector2(0.01, 0.01))
	assert_float(p.modulate.a).is_equal_approx(0.0, 0.01)
