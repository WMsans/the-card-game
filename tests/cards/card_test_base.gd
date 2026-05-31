class_name CardTestBase
extends GdUnitTestSuite

class HasReq extends CardScript:
	func has_request() -> bool: return true

func strike_def(id: int) -> CardDefinition:
	for d in CardDatabase.load_deck("res://src/data/decks/strike.csv", "strike"):
		if d.id == id:
			return d
	return null

func fresh_engine() -> GameEngine:
	var state := GameState.new(123)
	var eng := GameEngine.new(state)
	eng.setup(TestFactory.simple_deck(), TestFactory.simple_deck())
	eng.apply(Action.mulligan([]))
	eng.apply(Action.mulligan([]))
	return eng

func place_on_board(eng: GameEngine, pidx: int, def: CardDefinition) -> CardInstance:
	var ci := eng.state.make_instance(def)
	ci.zone = Enums.Zone.BOARD
	eng.state.players[pidx].board.append(ci)
	return ci

func put_in_hand(eng: GameEngine, pidx: int, def: CardDefinition) -> CardInstance:
	var ci := eng.state.make_instance(def)
	ci.zone = Enums.Zone.HAND
	eng.state.players[pidx].hand.append(ci)
	eng.state.players[pidx].tickets_total = 20
	return ci
