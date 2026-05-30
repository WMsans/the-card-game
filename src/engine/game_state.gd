class_name GameState
extends RefCounted

var players: Array[PlayerState] = []
var active_player: int = 0
var first_player: int = 0
var turn_number: int = 0
var phase: int = Enums.Phase.SETUP
var rng: SeededRng
var bus: EventBus
var pending_choice: PendingChoice = null
var winner: int = -1
var _next_instance_id: int = 1

func _init(seed_value: int) -> void:
	rng = SeededRng.new(seed_value)
	bus = EventBus.new()
	players = [PlayerState.new(), PlayerState.new()]

func opponent() -> int:
	return 1 - active_player

func active() -> PlayerState:
	return players[active_player]

func make_instance(def: CardDefinition) -> CardInstance:
	var ci := CardInstance.new(_next_instance_id, def)
	ci.card_script = CardScriptRegistry.get_script_for(def.deck_color, def.id)
	_next_instance_id += 1
	return ci
