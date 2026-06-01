# tests/test_game_settings.gd
extends GdUnitTestSuite

const PATH := "user://test_settings.cfg"

func before_test() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

func test_defaults_when_no_file() -> void:
	var s := GameSettings.new(PATH)
	s.load()
	assert_bool(s.fullscreen).is_false()
	assert_bool(s.vsync).is_true()

func test_save_then_load_round_trips() -> void:
	var s := GameSettings.new(PATH)
	s.fullscreen = true
	s.vsync = false
	s.save()
	var s2 := GameSettings.new(PATH)
	s2.load()
	assert_bool(s2.fullscreen).is_true()
	assert_bool(s2.vsync).is_false()
