extends GdUnitTestSuite

func _inst() -> Node:
	var p = load("res://src/ui/overlays/minimize_bar.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_show_bar_sets_title() -> void:
	var bar = _inst()
	bar.show_bar("Choose 2 cards")
	assert_str(bar.find_child("Title").text).is_equal("Choose 2 cards")

func test_expand_pressed_signal() -> void:
	var bar = _inst()
	var btn: Button = bar.find_child("ExpandButton")
	assert_bool(btn.pressed.is_connected(bar._on_expand_pressed)).is_true()
	var got := {"emitted": false}
	bar.expand_pressed.connect(func(): got["emitted"] = true)
	bar._on_expand_pressed()
	assert_bool(got["emitted"]).is_true()

func test_expand_button_has_game_theme() -> void:
	var bar = _inst()
	var tab: HBoxContainer = bar.find_child("Tab") as HBoxContainer
	assert_that(tab.theme).is_not_null()

func test_hide_bar_hides_tab() -> void:
	var bar = _inst()
	bar.show_bar("Test")
	await get_tree().create_timer(0.5).timeout
	bar.hide_bar()
	await get_tree().create_timer(0.4).timeout
	assert_bool(bar.find_child("Tab").visible).is_false()
