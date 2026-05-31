# tests/cards/writing/writing_test_base.gd
class_name WritingTestBase
extends CardTestBase

func writing_def(id: int) -> CardDefinition:
	for d in CardDatabase.load_deck("res://src/data/decks/writing.csv", "writing"):
		if d.id == id:
			return d
	return null

func oranges_in_hand(eng: GameEngine, p: int) -> int:
	var n := 0
	for c in eng.state.players[p].hand:
		if OrangeToken.is_orange(c):
			n += 1
	return n
