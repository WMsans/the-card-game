extends Control

signal quit_to_menu

const HUMAN := 0
const THEME := preload("res://src/ui/theme/game_theme.tres")
const MINIMIZE_STAGGER := 0.05
const MINIMIZE_DURATION := 0.25
const EXPAND_DURATION := 0.35
const DIM_FADE_DURATION := 0.3
const FEATURE_CENTER := Vector2(BoardLayout.CENTER_X, BoardLayout.SCREEN.y * 0.5)
const FEATURE_SCALE := 1.0

var state: GameState
var engine: GameEngine
var _selected_attacker: int = -1
var _deck0_path: String
var _deck1_path: String
var _dragging_id: int = -1
var _targeting_for_choice: bool = false
var _target_candidates: Array = []
var _director := CombatDirector.new()
var _action_cue := ActionCue.new()
var _anim_busy: bool = false
var _minimized_overlay: CanvasLayer = null
# tracked for future re-entrancy guards and integration tests
var _active_overlay: CanvasLayer = null
var _rest_transforms: Dictionary = {}
var _tweens: Array[Tween] = []
var _bg: BalatroBg = null

@onready var opp_board: Node2D = $Table/OppBoard
@onready var player_board: Node2D = $Table/PlayerBoard
@onready var hand_view: Node2D = $Table/PlayerHand
@onready var opp_hand: Node2D = $Table/OppHand
@onready var _player_deck = $Table/PlayerDeck
@onready var _player_discard = $Table/PlayerDiscard
@onready var _opp_deck = $Table/OppDeck
@onready var _opp_discard = $Table/OppDiscard
@onready var _player_trap = $Table/PlayerTrap
@onready var _opp_trap = $Table/OppTrap
@onready var _tickets = $Table/PlayerTickets
@onready var _end_turn: Button = $EndTurnButton
@onready var _arrow: Node2D = $ArrowLayer
@onready var _mulligan: MulliganPanel = $MulliganPanel
@onready var _select = $CardSelectPanel
@onready var _leader_prompt = $LeaderCostPrompt
@onready var _game_over = $GameOverPanel
@onready var _drop_zones: DropZoneOverlay = $DropZoneLayer
@onready var _option_prompt = $OptionPrompt
@onready var _trap_reveal = $TrapRevealOverlay
@onready var _flight = $Table/CardFlightLayer
@onready var _hand_choice = $HandChoice
@onready var _pile_overlay = $PileOverlay
@onready var _minimize_bar = $MinimizeBar
@onready var _hand_choice_dim: ColorRect = $Table/HandChoiceDim

func _ready() -> void:
	_hand_choice._dim_node = _hand_choice_dim
	hand_view.z_index = 1
	_end_turn.pressed.connect(_on_end_turn_pressed)
	hand_view.card_drag_released.connect(_on_hand_card_drag_released)
	hand_view.card_drag_started.connect(_on_hand_card_drag_started)
	player_board.unit_clicked.connect(handle_unit_clicked)
	opp_board.unit_clicked.connect(handle_unit_clicked)
	hand_view.card_departed.connect(_on_card_departed)
	player_board.card_departed.connect(_on_card_departed)
	opp_board.card_departed.connect(_on_card_departed)
	_opp_deck.clicked.connect(handle_deck_target_clicked)
	_player_deck.clicked.connect(_on_pile_clicked.bind(Enums.Zone.DECK, HUMAN))
	_player_discard.clicked.connect(_on_pile_clicked.bind(Enums.Zone.DISCARD, HUMAN))
	_opp_discard.clicked.connect(_on_pile_clicked.bind(Enums.Zone.DISCARD, 1 - HUMAN))
	_player_trap.clicked.connect(_on_trap_pile_clicked.bind(HUMAN))
	_opp_trap.clicked.connect(_on_trap_pile_clicked.bind(1 - HUMAN))
	_mulligan.confirmed.connect(func(idx): _active_overlay = null; apply_action(Action.mulligan(idx)))
	_select.confirmed.connect(func(idx): _active_overlay = null; apply_action(Action.resolve_choice({"indices": idx})))
	_hand_choice.confirmed.connect(_on_hand_choice_confirmed)
	_option_prompt.picked.connect(func(i): _active_overlay = null; apply_action(Action.resolve_choice({"option": i})))
	_trap_reveal.picked.connect(func(i): _active_overlay = null; apply_action(Action.resolve_choice({"option": i})))
	_game_over.play_again.connect(_on_play_again)
	_game_over.quit.connect(func(): get_tree().quit())
	_game_over.main_menu.connect(func(): quit_to_menu.emit())
	_select.minimize_requested.connect(_on_overlay_minimize.bind(_select))
	_hand_choice.minimize_requested.connect(_on_overlay_minimize.bind(_hand_choice))
	_option_prompt.minimize_requested.connect(_on_overlay_minimize.bind(_option_prompt))
	_trap_reveal.minimize_requested.connect(_on_overlay_minimize.bind(_trap_reveal))
	_leader_prompt.minimize_requested.connect(_on_overlay_minimize.bind(_leader_prompt))
	_mulligan.minimize_requested.connect(_on_overlay_minimize.bind(_mulligan))
	_minimize_bar.expand_pressed.connect(_on_overlay_expand)
	theme = THEME
	JuicyButton.apply(_end_turn)

func attach_background(bg: BalatroBg) -> void:
	_bg = bg
	if _bg != null and not _bg.foreground_offset.is_connected(_on_foreground_offset):
		_bg.foreground_offset.connect(_on_foreground_offset)

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
	var before := _snapshot_zones()
	var from := state.bus.log.size()
	engine.apply(action)
	var events := state.bus.log.slice(from)
	var plan := _enrich(TransitionPlan.compute(before, _snapshot_zones()))
	_anim_busy = true
	if CombatDirector.has_attack(events):
		await _director.play(events, self)
	else:
		await _run_bespoke(events)
	render_all(plan)
	_spawn_pile_travelers(plan)
	_play_flourishes(events)
	if not CombatDirector.has_attack(events):
		await _action_cue.play(self, events)
	_anim_busy = false
	_post_action()

func render_all(plan: Array = []) -> void:
	var you := state.players[HUMAN]
	var opp := state.players[1 - HUMAN]
	player_board.render(you.board, 0, plan)
	opp_board.render(opp.board, 1, plan)
	hand_view.render(you.hand, 0, plan)
	opp_hand.set_count(opp.hand.size())
	_player_deck.set_count(you.deck.size())
	_player_discard.set_count(you.discard.size())
	_opp_deck.set_count(opp.deck.size())
	_opp_discard.set_count(opp.discard.size())
	_player_trap.set_count(you.set_traps.size())
	_opp_trap.set_count(opp.set_traps.size())
	_tickets.set_tickets(you.tickets_tapped, you.tickets_total)

func _snapshot_zones() -> Dictionary:
	var snap := {}
	for p in range(state.players.size()):
		var ps: PlayerState = state.players[p]
		for c in ps.deck:
			snap[c.instance_id] = {"zone": Enums.Zone.DECK, "player": p}
		for c in ps.hand:
			snap[c.instance_id] = {"zone": Enums.Zone.HAND, "player": p}
		for c in ps.board:
			snap[c.instance_id] = {"zone": Enums.Zone.BOARD, "player": p}
		for c in ps.discard:
			snap[c.instance_id] = {"zone": Enums.Zone.DISCARD, "player": p}
	return snap

func _enrich(raw: Array) -> Array:
	var out: Array = []
	for t in raw:
		var e: Dictionary = t.duplicate()
		if t["from"] == Enums.Zone.DECK or t["from"] == Enums.Zone.DISCARD:
			e["from_pos"] = _flight.to_local(FlightAnchors.of(t["from"], t["player"], self)) - BoardLayout.CARD_PIVOT
		if t["to"] == Enums.Zone.DECK or t["to"] == Enums.Zone.DISCARD:
			e["to_pos"] = _flight.to_local(FlightAnchors.of(t["to"], t["player"], self)) - BoardLayout.CARD_PIVOT
		out.append(e)
	return out

func _spawn_pile_travelers(plan: Array) -> void:
	var mill_i := 0
	var resh_i := 0
	for e in plan:
		var from_pile: bool = e["from"] == Enums.Zone.DECK or e["from"] == Enums.Zone.DISCARD
		var to_pile: bool = e["to"] == Enums.Zone.DECK or e["to"] == Enums.Zone.DISCARD
		if not (from_pile and to_pile):
			continue
		if e["from"] == Enums.Zone.DECK and e["to"] == Enums.Zone.DISCARD:
			_flight.spawn_traveler(_find_card(e["instance_id"]), e["from_pos"], e["to_pos"],
				float(mill_i) * 0.05)
			mill_i += 1
		elif e["from"] == Enums.Zone.DISCARD and e["to"] == Enums.Zone.DECK:
			if resh_i < 5:
				_flight.spawn_traveler(null, e["from_pos"], e["to_pos"], float(resh_i) * 0.04)
				resh_i += 1

func _on_card_departed(cv: CardView, to_pos: Vector2) -> void:
	_flight.take_leaver(cv, to_pos)

func _find_card(iid: int) -> CardInstance:
	for p in state.players:
		for coll in [p.deck, p.hand, p.board, p.discard]:
			for c in coll:
				if c.instance_id == iid:
					return c
	return null

func _find_card_view_any(iid: int) -> CardView:
	for view in [hand_view, player_board, opp_board, opp_hand]:
		if "card_views" in view and view.card_views.has(iid):
			return view.card_views[iid]
	return null

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
		if pc.kind == "intercept":
			await _show_readonly_intercept(pc)
		await get_tree().create_timer(0.2).timeout
		apply_action(AiController.choice_action(engine))
		return
	match pc.kind:
		"mulligan":
			var hand := state.players[HUMAN].hand
			var excluded := []
			for c in hand:
				if c.definition.type == Enums.CardType.LEADER:
					excluded.append(c.instance_id)
			_hand_choice.start(hand_view, hand, 2, 2, "Choose 2 cards to discard", excluded)
			_active_overlay = _hand_choice
		"discard_to_limit":
			var n: int = pc.data["count"]
			_hand_choice.start(hand_view, state.players[HUMAN].hand, n, n, "Discard %d card(s)" % n)
			_active_overlay = _hand_choice
		"intercept":
			var spec: ChoiceSpec = pc.data["spec"]
			_trap_reveal.show_reveal(spec.cards[0], spec.title, spec.labels, true)
			_active_overlay = _trap_reveal
		"trash_choice":
			var spec2: ChoiceSpec = pc.data["spec"]
			_option_prompt.show_options(spec2.labels, spec2.title, pc.data.get("source_card"))
			_active_overlay = _option_prompt
		"card_effect":
			_route_card_effect(pc)

func _route_card_effect(pc: PendingChoice) -> void:
	var spec: ChoiceSpec = pc.data["spec"]
	match spec.ui_shape:
		"select_cards":
			if _is_hand_pool(spec.cards):
				_hand_choice.start(hand_view, spec.cards, spec.min_n, spec.max_n, spec.title)
				_active_overlay = _hand_choice
			else:
				_select.show_selection(spec.cards, spec.min_n, spec.max_n, spec.title)
				_active_overlay = _select
		"choose_option":
			_option_prompt.show_options(spec.labels, spec.title, pc.data.get("source_card"))
			_active_overlay = _option_prompt
		"select_target":
			_begin_target_selection(spec)
			_active_overlay = null

func _is_hand_pool(cards: Array) -> bool:
	if cards.is_empty():
		return false
	var hand_ids := {}
	for c in state.players[HUMAN].hand:
		hand_ids[c.instance_id] = true
	for c in cards:
		if not hand_ids.has(c.instance_id):
			return false
	return true

func _show_readonly_intercept(pc: PendingChoice) -> void:
	var spec: ChoiceSpec = pc.data["spec"]
	FeedbackFx.bump_pile(_opp_trap if pc.player != HUMAN else _player_trap, 1.0)
	_trap_reveal.show_reveal(spec.cards[0], spec.title, spec.labels, false)
	await get_tree().create_timer(FeedbackFx.HOLD_TIME).timeout
	_trap_reveal.dismiss()

func _begin_target_selection(spec: ChoiceSpec) -> void:
	_target_candidates = []
	for u in spec.cards:
		_target_candidates.append(u.instance_id)
	_targeting_for_choice = true
	_refresh_highlights()

func _run_ai_turn() -> void:
	await get_tree().create_timer(0.35).timeout
	if state.phase == Enums.Phase.GAME_OVER or state.active_player == HUMAN:
		return
	apply_action(AiController.choose_action(engine))

func _show_game_over() -> void:
	_game_over.show_result(state.winner, HUMAN)
	_active_overlay = _game_over

static func _deck_color_from(path: String) -> String:
	return path.get_file().replace(".csv", "")

func _on_play_again() -> void:
	_active_overlay = null
	_game_over.visible = false
	start_game(randi(), _deck0_path, _deck1_path)

func _on_end_turn_pressed() -> void:
	if _anim_busy:
		return
	if state.active_player == HUMAN and state.pending_choice == null:
		apply_action(Action.end_turn())

func _on_hand_choice_confirmed(indices: Array) -> void:
	_active_overlay = null
	match state.pending_choice.kind:
		"mulligan":
			apply_action(Action.mulligan(indices))
		_:
			apply_action(Action.resolve_choice({"indices": indices}))

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
	if _targeting_for_choice:
		for iid in player_board.card_views:
			var cv: CardView = player_board.card_views[iid]
			cv.set_highlight(CardHighlight.State.SELECTABLE if _target_candidates.has(iid) else CardHighlight.State.NONE)
		for iid in opp_board.card_views:
			var cv: CardView = opp_board.card_views[iid]
			cv.set_highlight(CardHighlight.State.SELECTABLE if _target_candidates.has(iid) else CardHighlight.State.NONE)

func handle_drop(instance_id: int, drop_zone: String) -> bool:
	var legal: Array = engine.get_legal_actions()
	var by_tickets: Action = CardInput.play_from_drop(instance_id, drop_zone, legal, false)
	var by_discard: Action = CardInput.play_from_drop(instance_id, drop_zone, legal, true)
	if by_tickets != null and by_discard != null:
		_leader_prompt.show_prompt()
		_active_overlay = _leader_prompt
		var handler := func(by_disc: bool):
			_active_overlay = null
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
	if _anim_busy:
		return
	if _targeting_for_choice:
		if _target_candidates.has(instance_id):
			_targeting_for_choice = false
			apply_action(Action.resolve_choice({"target_ids": [instance_id]}))
		return
	if _selected_attacker == -1:
		if instance_id in legal_attacker_ids():
			_selected_attacker = instance_id
			var cv: CardView = player_board.card_views.get(instance_id)
			if cv:
				_arrow.begin(cv.global_position + cv.size * 0.5)
	else:
		_resolve_attack_target({"unit": instance_id})

func handle_deck_target_clicked() -> void:
	if _anim_busy:
		return
	if _selected_attacker != -1:
		_resolve_attack_target({"deck": true})
		return
	if _targeting_for_choice:
		return
	_on_pile_clicked(Enums.Zone.DECK, 1 - HUMAN)

func _on_pile_clicked(zone: int, player: int) -> void:
	if _anim_busy or _pile_overlay.is_open() or _selected_attacker != -1:
		return
	if _active_overlay != null and _minimized_overlay == null:
		return
	var ps: PlayerState = state.players[player]
	var cards: Array[CardInstance] = ps.deck if zone == Enums.Zone.DECK else ps.discard
	if cards.is_empty():
		return
	var pos := FlightAnchors.of(zone, player, self)
	_pile_overlay.open(cards, pos, _pile_title(zone, player), player != HUMAN)

func _on_trap_pile_clicked(player: int) -> void:
	if _anim_busy or _pile_overlay.is_open() or _selected_attacker != -1:
		return
	if _active_overlay != null and _minimized_overlay == null:
		return
	var cards: Array[CardInstance] = state.players[player].set_traps
	if cards.is_empty():
		return
	var pos := FlightAnchors.of(Enums.Zone.TRAP_SET, player, self)
	var title := "Your Traps" if player == HUMAN else "Opponent's Traps"
	_pile_overlay.open(cards, pos, title, player != HUMAN)

func _pile_title(zone: int, player: int) -> String:
	var who := "Your" if player == HUMAN else "Opponent's"
	var what := "Deck" if zone == Enums.Zone.DECK else "Discard"
	return "%s %s" % [who, what]

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
	if _anim_busy:
		return
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
	Flourishes.play(self, events, CombatDirector.has_attack(events))
	for e in events:
		if e.type == Enums.EventType.TURN_STARTED:
			$Banner.show_turn(e.data["player"] == HUMAN)
			_director.reset_ramp()
			_action_cue.reset_ramp()

func _run_bespoke(events: Array) -> void:
	for e in events:
		if e.type == Enums.EventType.CARD_PLAYED:
			match e.data.get("card_type", -1):
				Enums.CardType.SPELL:
					await _feature_spell(e.data.get("instance", -1), e.data.get("player", -1))
				Enums.CardType.TRAP:
					await _feature_trap_deploy(e.data.get("instance", -1), e.data.get("player", -1))

func _on_overlay_minimize(overlay: CanvasLayer) -> void:
	if _minimized_overlay != null:
		return
	if overlay.has_method("on_minimize"):
		overlay.on_minimize()
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()
	_minimized_overlay = overlay
	var dim: Control = overlay.get_dim_node()
	var tab: Control = _minimize_bar.find_child("Tab")
	if tab == null:
		return
	var tab_pos := tab.global_position
	var nodes: Array[Node] = overlay.get_animatable_nodes()
	_rest_transforms.clear()
	for node in nodes:
		if node == null:
			continue
		_rest_transforms[node.get_instance_id()] = {
			"position": node.global_position,
			"scale": node.scale
		}

	for i in range(nodes.size()):
		var node: Node = nodes[nodes.size() - 1 - i]
		if node == null:
			continue
		var tw := node.create_tween()
		_tweens.push_back(tw)
		tw.tween_interval(MINIMIZE_STAGGER * float(i))
		tw.parallel().tween_property(node, "global_position", tab_pos, MINIMIZE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(node, "scale", Vector2.ZERO, MINIMIZE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	if dim != null:
		if dim is ColorRect:
			_rest_transforms["dim_color"] = dim.color
		else:
			_rest_transforms["dim_modulate"] = dim.modulate
		var tw := dim.create_tween()
		_tweens.push_back(tw)
		if dim is ColorRect:
			tw.tween_property(dim, "color:a", 0.0, DIM_FADE_DURATION).set_trans(Tween.TRANS_CUBIC)
		else:
			tw.tween_property(dim, "modulate:a", 0.0, DIM_FADE_DURATION).set_trans(Tween.TRANS_CUBIC)

	var final_tw := create_tween()
	_tweens.push_back(final_tw)
	final_tw.tween_interval(MINIMIZE_DURATION + MINIMIZE_STAGGER * float(nodes.size()))
	final_tw.tween_callback(func():
		for node in nodes:
			if node != null:
				node.visible = false
		if dim != null:
			dim.visible = false
		_minimize_bar.show_bar(_overlay_title(overlay))
	)

func _on_overlay_expand() -> void:
	var overlay := _minimized_overlay
	if overlay == null:
		return
	if overlay.has_method("on_expand"):
		overlay.on_expand()
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()
	_minimize_bar.hide_bar()
	var dim: Control = overlay.get_dim_node()
	var nodes: Array[Node] = overlay.get_animatable_nodes()
	var tab: Control = _minimize_bar.find_child("Tab")
	if tab == null:
		return
	var tab_pos := tab.global_position

	if dim != null:
		dim.visible = true
		var tw := dim.create_tween()
		_tweens.push_back(tw)
		if dim is ColorRect:
			var orig_color: Color = _rest_transforms.get("dim_color", Color(0, 0, 0, 0.55))
			dim.color = Color(orig_color, 0.0)
			tw.tween_property(dim, "color:a", orig_color.a, DIM_FADE_DURATION).set_trans(Tween.TRANS_CUBIC)
		else:
			var orig_mod: Color = _rest_transforms.get("dim_modulate", Color(1, 1, 1, 1.0))
			dim.modulate = Color(orig_mod, 0.0)
			tw.tween_property(dim, "modulate:a", orig_mod.a, DIM_FADE_DURATION).set_trans(Tween.TRANS_CUBIC)

	for i in range(nodes.size()):
		var node: Node = nodes[i]
		if node == null:
			continue
		var rest: Dictionary = _rest_transforms.get(node.get_instance_id(), {"position": node.global_position, "scale": Vector2.ONE})
		var rest_pos: Vector2 = rest["position"]
		var rest_scale: Vector2 = rest["scale"]
		node.visible = true
		node.global_position = tab_pos
		node.scale = Vector2.ZERO
		var tw := node.create_tween()
		_tweens.push_back(tw)
		tw.tween_interval(MINIMIZE_STAGGER * float(i))
		tw.parallel().tween_property(node, "global_position", rest_pos, EXPAND_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(node, "scale", rest_scale, EXPAND_DURATION).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	_minimized_overlay = null
	_rest_transforms.clear()

func _overlay_title(overlay: CanvasLayer) -> String:
	var label: Label = overlay.find_child("Title")
	if label != null:
		return label.text
	label = overlay.find_child("Label")
	if label != null:
		return label.text
	label = overlay.find_child("TrapName")
	if label != null:
		return label.text
	label = overlay.find_child("PromptLabel")
	if label != null:
		return label.text
	return "Choose"

func _feature_spell(iid: int, player: int) -> void:
	var cv := _find_card_view_any(iid)
	if cv == null:
		return
	cv.z_index = 300
	var spd := _action_cue.anim_speed
	var center_topleft := FEATURE_CENTER - cv.size * FEATURE_SCALE * 0.5
	var tw := cv.create_tween().set_parallel(true)
	tw.tween_property(cv, "global_position", center_topleft, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2(FEATURE_SCALE, FEATURE_SCALE), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	CardJuice.spring_wiggle(cv, 10.0, spd)
	await get_tree().create_timer(FeedbackFx.HOLD_TIME / maxf(spd, 0.01)).timeout
	var discard_pos := FlightAnchors.of(Enums.Zone.DISCARD, player, self) - cv.size * cv.scale * 0.5
	await CardFlight.fly_out(cv, discard_pos).finished
	cv.z_index = 0

func _feature_trap_deploy(iid: int, player: int) -> void:
	var cv := _find_card_view_any(iid)
	if cv == null:
		return
	cv.z_index = 300
	var spd := _action_cue.anim_speed
	var center_topleft := FEATURE_CENTER - cv.size * FEATURE_SCALE * 0.5
	var tw := cv.create_tween().set_parallel(true)
	tw.tween_property(cv, "global_position", center_topleft, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2(FEATURE_SCALE, FEATURE_SCALE), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	await get_tree().create_timer(FeedbackFx.HOLD_TIME / maxf(spd, 0.01)).timeout
	cv.set_face_down(true)
	var pile_pos := FlightAnchors.of(Enums.Zone.TRAP_SET, player, self)
	var to_topleft := pile_pos - cv.size * (cv.base_scale * 0.55) * 0.5
	await CardFlight.flourish_arc(cv, to_topleft, Vector2(-220, -120), spd).finished
	var pile: Control = _player_trap if player == HUMAN else _opp_trap
	FeedbackFx.bump_pile(pile, spd)
	cv.z_index = 0

func _on_foreground_offset(offset: Vector2) -> void:
	$Table.position = offset
