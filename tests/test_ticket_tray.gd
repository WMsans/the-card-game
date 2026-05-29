extends GdUnitTestSuite

func _spawn() -> Node:
	var t: Node = load("res://src/ui/table/ticket_tray.tscn").instantiate()
	add_child(t)
	auto_free(t)
	return t

func test_draws_total_pips_with_tapped_filled() -> void:
	var tray := _spawn()
	tray.set_tickets(3, 5)
	assert_int(tray.get_child_count()).is_equal(5)
	assert_int(tray.filled_count()).is_equal(3)
