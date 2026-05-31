extends AudioTestBase

func test_every_audio_id_resolves_to_a_non_default_script() -> void:
	var default := DefaultCard.new()
	for d in CardDatabase.load_deck("res://src/data/decks/audio.csv", "audio"):
		var s := CardScriptRegistry.get_script_for("audio", d.id)
		assert_bool(s.get_script() == default.get_script()).override_failure_message(
			"audio id %d has no script" % d.id).is_false()
