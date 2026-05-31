# tests/cards/writing/test_writing_registry.gd
extends WritingTestBase

func test_every_writing_id_resolves_to_a_non_default_script() -> void:
	var default := DefaultCard.new()
	for d in CardDatabase.load_deck("res://src/data/decks/writing.csv", "writing"):
		var s := CardScriptRegistry.get_script_for("writing", d.id)
		assert_bool(s.get_script() == default.get_script()).override_failure_message(
			"writing id %d has no script" % d.id).is_false()

func test_orange_token_registered() -> void:
	var s := CardScriptRegistry.get_script_for("writing", OrangeToken.ID)
	assert_bool(s is OrangeCard).is_true()
