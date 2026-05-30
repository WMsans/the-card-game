extends GdUnitTestSuite

func _spawn() -> Node:
	var p: Node = load("res://src/ui/table/pile_view.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_count_badge_reflects_size() -> void:
	var p := _spawn()
	p.set_count(17)
	assert_str(p.find_child("Count").text).is_equal("17")

func test_empty_pile_hides_back() -> void:
	var p := _spawn()
	p.set_count(0)
	assert_bool(p.find_child("Back").visible).is_false()
