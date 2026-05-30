extends Control

const HUMAN := 0
const THEME := preload("res://src/ui/theme/game_theme.tres")

var state: GameState
var engine: GameEngine
var _selected_attacker: int = -1
var _deck0_path: String
var _deck1_path: String
var _dragging_id: int = -1

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
@onready var _arrow: Node2D = $ArrowLayer
@onready var _mulligan: MulliganPanel = $MulliganPanel
@onready var _discard = $DiscardPanel
@onready var _leader_prompt = $LeaderCostPrompt
@onready var _game_over = $GameOverPanel
@onready var _drop_zones: DropZoneOverlay = $DropZoneLayer

func _ready() -> void:
	_end_turn.pressed.connect(_on_end_turn_pressed)
	hand_view.card_drag_released.connect(_on_hand_card_drag_released)
	hand_view.card_drag_started.connect(_on_hand_card_drag_started)
	player_board.unit_clicked.connect(handle_unit_clicked)
	opp_board.unit_clicked.connect(handle_unit_clicked)
	_opp_deck.clicked.connect(handle_deck_target_clicked)
	_mulligan.confirmed.connect(func(idx): apply_action(Action.mulligan(idx)))
	_discard.confirmed.connect(func(idx): apply_action(Action.resolve_choice({"indices": idx})))
	_game_over.play_again.connect(_on_play_again)
	_game_over.quit.connect(func(): get_tree().quit())
	theme = THEME
	JuicyButton.apply(_end_turn)

func start_game(seed_value: int, deck0_path: String, deck1_path: String) -> void:
	_deck0_path = deck0_path
	_deck1_path = deck1_path
	state = GameState.new(seed_value)
	engine = GameEngine.new(state)
	var d0: Array[CardDefinition] = CardDatabase.load_deck(deck0_path, _deck_color_from(deck0_path))
	var d1: Array[CardDefinition] = CardDatabase.load_deck(deck1_path, _deck_color_from(deck1_path))
	engine.setup(d0, d1)
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
		_show_game_over()
		return
	if state.pending_choice != null:
		_route_pending_choice()
		return
	if state.active_player != HUMAN:
		_run_ai_turn()

func _route_pending_choice() -> void:
	var pc := state.pending_choice
	if pc.player != HUMAN:
		await get_tree().create_timer(0.2).timeout
		apply_action(AiController.choice_action(engine))
		return
	match pc.kind:
		"mulligan":
			_mulligan.show_hand(state.players[HUMAN].hand)
		"discard_to_limit":
			_discard.show_hand(state.players[HUMAN].hand, pc.data["count"])

func _run_ai_turn() -> void:
	await get_tree().create_timer(0.35).timeout
	if state.phase == Enums.Phase.GAME_OVER or state.active_player == HUMAN:
		return
	apply_action(AiController.choose_action(engine))

func _show_game_over() -> void:
	_game_over.show_result(state.winner, HUMAN)

static func _deck_color_from(path: String) -> String:
	return path.get_file().replace(".csv", "")

func _on_play_again() -> void:
	_game_over.visible = false
	start_game(randi(), _deck0_path, _deck1_path)

func _on_end_turn_pressed() -> void:
	if state.active_player == HUMAN and state.pending_choice == null:
		apply_action(Action.end_turn())

func _refresh_highlights() -> void:
	if engine == null:
		return
	var legal: Array = engine.get_legal_actions()
	var playable_ids: Array = []
	var attacker_ids: Array = []
	for a in legal:
		if a.type == Enums.ActionType.PLAY_CARD:
			playable_ids.append(a.params["instance_id"])
		elif a.type == Enums.ActionType.DECLARE_ATTACK:
			attacker_ids.append(a.params["attacker_id"])
	for iid in hand_view.card_views:
		var cv: CardView = hand_view.card_views[iid]
		cv.set_playable(playable_ids.has(iid))
	for iid in player_board.card_views:
		var cv: CardView = player_board.card_views[iid]
		cv.set_attackable(attacker_ids.has(iid))

func handle_drop(instance_id: int, drop_zone: String) -> bool:
	var legal: Array = engine.get_legal_actions()
	var by_tickets: Action = CardInput.play_from_drop(instance_id, drop_zone, legal, false)
	var by_discard: Action = CardInput.play_from_drop(instance_id, drop_zone, legal, true)
	if by_tickets != null and by_discard != null:
		_leader_prompt.show_prompt()
		var handler := func(by_disc: bool):
			if by_disc:
				apply_action(by_discard)
			else:
				apply_action(by_tickets)
		_leader_prompt.chosen.connect(handler, CONNECT_ONE_SHOT)
		return true
	if by_discard != null:
		apply_action(by_discard)
		return true
	if by_tickets != null:
		apply_action(by_tickets)
		return true
	render_all()
	return false

func handle_unit_clicked(instance_id: int) -> void:
	if _selected_attacker == -1:
		if instance_id in legal_attacker_ids():
			_selected_attacker = instance_id
			var cv: CardView = player_board.card_views.get(instance_id)
			if cv:
				_arrow.begin(cv.global_position + cv.size * 0.5)
	else:
		_resolve_attack_target({"unit": instance_id})

func handle_deck_target_clicked() -> void:
	if _selected_attacker != -1:
		_resolve_attack_target({"deck": true})

func _resolve_attack_target(target: Dictionary) -> void:
	var legal: Array = engine.get_legal_actions()
	var act = CardInput.attack_from_target(_selected_attacker, target, legal)
	_selected_attacker = -1
	_arrow.end()
	if act != null:
		apply_action(act)
	else:
		render_all()

func _cancel_attack() -> void:
	_selected_attacker = -1
	_arrow.end()

func _unhandled_input(event: InputEvent) -> void:
	if _selected_attacker != -1 and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_attack()
		get_viewport().set_input_as_handled()

func legal_attacker_ids() -> Array:
	var legal: Array = engine.get_legal_actions()
	var ids: Array = []
	for a in legal:
		if a.type == Enums.ActionType.DECLARE_ATTACK:
			ids.append(a.params["attacker_id"])
	return ids

func legal_play_ids() -> Array:
	var legal: Array = engine.get_legal_actions()
	var ids: Array = []
	for a in legal:
		if a.type == Enums.ActionType.PLAY_CARD:
			ids.append(a.params["instance_id"])
	return ids

func _on_hand_card_drag_released(instance_id: int, _at: Vector2) -> void:
	_dragging_id = -1
	var in_zone := _drop_zones.is_hovering_zone()
	_drop_zones.clear()
	_tickets.clear_preview()
	if in_zone:
		handle_drop(instance_id, "play_zone")

func _on_hand_card_drag_started(instance_id: int) -> void:
	_dragging_id = instance_id
	if DragClassifier.advertises_zone(state, instance_id, HUMAN):
		_drop_zones.show_zones(_zone_rects_for(instance_id))

func _zone_rects_for(instance_id: int) -> Array:
	var inst := _find_hand_inst(instance_id)
	if inst != null and inst.definition.type == Enums.CardType.MINION:
		return [Rect2(360, 520, 1200, 260)]
	return [Rect2(360, 360, 1200, 420)]

func _find_hand_inst(instance_id: int) -> CardInstance:
	for c in state.players[HUMAN].hand:
		if c.instance_id == instance_id:
			return c
	return null

func _process(_delta: float) -> void:
	if _selected_attacker != -1:
		_arrow.point_at(get_global_mouse_position())
	if _dragging_id != -1:
		_update_drag_feedback()

func _update_drag_feedback() -> void:
	var cls := DragClassifier.classify(state, engine.get_legal_actions(), _dragging_id, HUMAN)
	var zstate := DropZoneOverlay.ZoneState.NEUTRAL
	if cls == DragClassifier.State.ACCEPTABLE:
		zstate = DropZoneOverlay.ZoneState.ACCEPTABLE
	elif cls == DragClassifier.State.UNAFFORDABLE:
		zstate = DropZoneOverlay.ZoneState.UNAFFORDABLE
	_drop_zones.set_hover(get_global_mouse_position(), zstate)
	if cls == DragClassifier.State.ACCEPTABLE and _drop_zones.is_hovering_zone():
		var inst := _find_hand_inst(_dragging_id)
		if inst != null:
			_tickets.preview_cost(inst.definition.ticket_cost)
	else:
		_tickets.clear_preview()

func _play_flourishes(events: Array) -> void:
	Flourishes.play(self, events)
	for e in events:
		if e.type == Enums.EventType.TURN_STARTED:
			$Banner.show_turn(e.data["player"] == HUMAN)