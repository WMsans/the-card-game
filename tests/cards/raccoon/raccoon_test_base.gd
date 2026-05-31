class_name RaccoonTestBase
extends CardTestBase

func raccoon_def(id: int) -> CardDefinition:
	for d in CardDatabase.load_deck("res://src/data/decks/raccoon.csv", "raccoon"):
		if d.id == id:
			return d
	return null

func seed_discard(eng: GameEngine, p: int, n: int) -> Array:
	var out: Array = []
	for i in range(n):
		var c := eng.state.make_instance(TestFactory.minion(1, 1, 1, 700 + i))
		c.zone = Enums.Zone.DISCARD
		eng.state.players[p].discard.append(c)
		out.append(c)
	return out
