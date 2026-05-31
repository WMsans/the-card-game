extends RaccoonTestBase

func test_every_raccoon_id_resolves_to_a_non_default_script() -> void:
	var default := DefaultCard.new()
	for d in CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "raccoon"):
		var s := CardScriptRegistry.get_script_for("raccoon", d.id)
		assert_bool(s.get_script() == default.get_script()).override_failure_message(
			"raccoon id %d has no script" % d.id).is_false()
