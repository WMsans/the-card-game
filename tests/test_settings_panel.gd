# tests/test_settings_panel.gd
extends GdUnitTestSuite

func _spawn() -> SettingsPanel:
	var p: SettingsPanel = load("res://src/ui/shell/settings_panel.tscn").instantiate()
	add_child(p)
	auto_free(p)
	return p

func test_back_button_emits_back_pressed() -> void:
	var p := _spawn()
	var fired := [false]
	p.back_pressed.connect(func() -> void: fired[0] = true)
	p.get_node("%Back").pressed.emit()
	assert_bool(fired[0]).is_true()

func test_toggles_reflect_initial_settings() -> void:
	var p := _spawn()
	var s := GameSettings.new("user://test_settings_panel.cfg")
	s.fullscreen = true
	s.vsync = false
	p.bind(s)
	assert_bool(p.get_node("%Fullscreen").button_pressed).is_true()
	assert_bool(p.get_node("%Vsync").button_pressed).is_false()

func test_toggling_fullscreen_updates_and_saves_settings() -> void:
	var p := _spawn()
	var s := GameSettings.new("user://test_settings_panel.cfg")
	p.bind(s)
	p.get_node("%Fullscreen").button_pressed = true
	p.get_node("%Fullscreen").toggled.emit(true)
	assert_bool(s.fullscreen).is_true()
	var reloaded := GameSettings.new("user://test_settings_panel.cfg")
	reloaded.load()
	assert_bool(reloaded.fullscreen).is_true()
