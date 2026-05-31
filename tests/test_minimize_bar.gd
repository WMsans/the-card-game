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
	assert_bool(bar._expand_btn.pressed.is_connected(bar._on_expand_pressed)).is_true()
	var got := {"emitted": false}
	bar.expand_pressed.connect(func(): got["emitted"] = true)
	bar._on_expand_pressed()
	assert_bool(got["emitted"]).is_true()
