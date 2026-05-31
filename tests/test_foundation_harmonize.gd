# tests/test_foundation_harmonize.gd
extends CardTestBase

class NoteStub extends CardScript:
	func reacts_to() -> Array: return [Enums.EventType.HARMONIZE]
	func active_zones() -> Array: return [Enums.Zone.BOARD]
	func react(card: CardInstance, _event: GameEvent, _ctx) -> void:
		if card.vars.get("harmonized", false): return
		card.vars["harmonized"] = true
		card.current_damage += 2

func test_harmonize_emits_event_and_buffs_notes_once() -> void:
	var eng := fresh_engine()
	var me := eng.state.active_player
	var note := place_on_board(eng, me, TestFactory.minion(2, 1, 4, 2))
	note.card_script = NoteStub.new()
	var ctx := EffectContext.new(eng, me)
	ctx.harmonize()
	assert_int(note.current_damage).is_equal(3)
	ctx.harmonize()  # second harmonize does not re-trigger
	assert_int(note.current_damage).is_equal(3)
