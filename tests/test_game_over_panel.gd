extends GdUnitTestSuite

func _spawn() -> Node:
	var p: Node = load("res://src/ui/overlays/game_over_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_main_menu_button_emits_main_menu_signal() -> void:
	var p := _spawn()
	var fired := [false]
	p.main_menu.connect(func() -> void: fired[0] = true)
	p.get_node("Panel/MainMenu").pressed.emit()
	assert_bool(fired[0]).is_true()
