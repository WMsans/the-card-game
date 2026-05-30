extends Control

const HUMAN := 0

var state: GameState
var engine: GameEngine

@onready var opp_board: Node2D = $Table/OppBoard
@onready var player_board: Node2D = $Table/PlayerBoard
@onready var hand_view: Node2D = $Table/PlayerHand
@onready var opp_hand: Node2D = $Table/OppHand
@onready var _player_deck = $Table/PlayerDeck
@onready var _player_discard = $Table/PlayerDiscard
@onready var _opp_deck = $Table/OppDeck
@onready var _opp_discard = $Table/OppDiscard
@onready var _player_leader = $Table/PlayerLeader
@onready var _opp_leader = $Table/OppLeader
@onready var _tickets = $Table/PlayerTickets
@onready var _end_turn: Button = $EndTurnButton

func _ready() -> void:
	_end_turn.pressed.connect(_on_end_turn_pressed)

func start_game(seed_value: int, deck0_path: String, deck1_path: String) -> void:
	state = GameState.new(seed_value)
	engine = GameEngine.new(state)
	var d0: Array[CardDefinition] = CardDatabase.load_deck(deck0_path, "P0")
	var d1: Array[CardDefinition] = CardDatabase.load_deck(deck1_path, "P1")
	engine.setup(d0, d1)
	_auto_resolve_mulligans()
	render_all()
	_post_action()

func apply_action(action: Action) -> void:
	var from := state.bus.log.size()
	engine.apply(action)
	var events := state.bus.log.slice(from)
	render_all()
	_play_flourishes(events)
	_post_action()

func render_all() -> void:
	var you := state.players[HUMAN]
	var opp := state.players[1 - HUMAN]
	player_board.render(you.board, 0)
	opp_board.render(opp.board, 1)
	hand_view.render(you.hand, 0)
	opp_hand.set_count(opp.hand.size())
	_player_deck.set_count(you.deck.size())
	_player_discard.set_count(you.discard.size())
	_opp_deck.set_count(opp.deck.size())
	_opp_discard.set_count(opp.discard.size())
	_player_leader.set_count(1 if you.leader else 0)
	_opp_leader.set_count(1 if opp.leader else 0)
	_tickets.set_tickets(you.tickets_tapped, you.tickets_total)

func _post_action() -> void:
	_refresh_highlights()
	_end_turn.disabled = state.active_player != HUMAN or state.pending_choice != null
	if state.phase == Enums.Phase.GAME_OVER:
		return
	if state.active_player != HUMAN and state.pending_choice == null:
		_take_opponent_turn_stub()

func _on_end_turn_pressed() -> void:
	if state.active_player == HUMAN and state.pending_choice == null:
		apply_action(Action.end_turn())

func _auto_resolve_mulligans() -> void:
	while state.pending_choice != null and state.pending_choice.kind == "mulligan":
		engine.apply(Action.mulligan([0, 1]))

func _take_opponent_turn_stub() -> void:
	await get_tree().create_timer(0.3).timeout
	if state.phase != Enums.Phase.GAME_OVER and state.active_player != HUMAN:
		apply_action(Action.end_turn())

func _refresh_highlights() -> void:
	pass

func _play_flourishes(events: Array) -> void:
	Flourishes.play(self, events)
	for e in events:
		if e.type == Enums.EventType.TURN_STARTED:
			$Banner.show_turn(e.data["player"] == HUMAN)