extends Control

const STRIKE := "res://src/data/decks/strike.csv"
const RACCOON := "res://src/data/decks/raccoon.csv"

var state: GameState
var engine: GameEngine

func _ready() -> void:
	if get_tree().current_scene != self:
		return
	build(12345)
	render()

func build(seed_value: int) -> void:
	state = GameState.new(seed_value)
	engine = GameEngine.new(state)
	var d0: Array[CardDefinition] = CardDatabase.load_deck(STRIKE, "Strike")
	var d1: Array[CardDefinition] = CardDatabase.load_deck(RACCOON, "Raccoon")
	engine.setup(d0, d1)
	engine.apply(Action.mulligan([0, 1]))
	engine.apply(Action.mulligan([0, 1]))
	render()

func render() -> void:
	var you := state.players[0]
	var opp := state.players[1]
	($PlayerBoard as Node2D).render(you.board, 0)
	($OppBoard as Node2D).render(opp.board, 1)
	($PlayerHand as Node2D).render(you.hand, 0)
	($OppHand as Node2D).set_count(opp.hand.size())
	($PlayerDeck as Node).set_count(you.deck.size())
	($PlayerDiscard as Node).set_count(you.discard.size())
	($OppDeck as Node).set_count(opp.deck.size())
	($OppDiscard as Node).set_count(opp.discard.size())
	($PlayerTickets as Node).set_tickets(you.tickets_tapped, you.tickets_total)
