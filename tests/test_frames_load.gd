extends GdUnitTestSuite

func test_all_frames_load_as_texture() -> void:
	for name in ["minion", "leader", "spell", "trap", "back"]:
		var path := "res://src/ui/assets/frames/%s.png" % name
		assert_bool(ResourceLoader.exists(path)).override_failure_message(
			"Missing frame: %s" % path).is_true()
		var tex := load(path)
		assert_object(tex).is_instanceof(Texture2D)
