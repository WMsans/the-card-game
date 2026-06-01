# tests/test_credits_panel.gd
extends GdUnitTestSuite

func _spawn() -> CreditsPanel:
	var p: CreditsPanel = load("res://src/ui/shell/credits_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_back_button_emits_back_pressed() -> void:
	var p := _spawn()
	var fired := [false]
	p.back_pressed.connect(func() -> void: fired[0] = true)
	p.get_node("%Back").pressed.emit()
	assert_bool(fired[0]).is_true()
