extends GdUnitTestSuite

func test_show_sets_text_for_player() -> void:
	var b: CanvasLayer = load("res://src/ui/overlays/turn_banner.tscn").instantiate()
	add_child(b)
	auto_free(b)
	b.show_turn(true)
	assert_str(b.find_child("Label").text).is_equal("Your Turn")
	b.show_turn(false)
	assert_str(b.find_child("Label").text).is_equal("Opponent's Turn")