class_name EffectContext
extends RefCounted

var engine: GameEngine
var pidx: int

func _init(e: GameEngine, p: int) -> void:
	engine = e
	pidx = p

func me() -> int: return pidx
func opponent() -> int: return 1 - pidx
func gs() -> GameState: return engine.state
func board(p: int) -> Array: return engine.state.players[p].board
func hand(p: int) -> Array: return engine.state.players[p].hand
func discard_pile(p: int) -> Array: return engine.state.players[p].discard
func counters(p: int) -> Dictionary: return engine.state.players[p].turn_counters

func draw(n: int = 1) -> void: engine._draw(pidx, n)
func mill(player: int, n: int) -> void: engine._mill(player, n)
func deal_deck_damage(player: int, n: int) -> void: engine._deck_damage(player, n)
func deal_damage(unit: CardInstance, n: int) -> void: engine._damage_unit(unit, n)
func kill(unit: CardInstance) -> void: engine._kill_unit(unit)
func discard_from_hand(card: CardInstance) -> void: engine._discard_from_hand(card)
func search_deck(pred: Callable) -> CardInstance: return engine._search_deck(pidx, pred)
func draw_specific(card: CardInstance) -> void: engine._draw_specific(pidx, card)
func summon_free(card: CardInstance) -> void: engine._summon_free(pidx, card)
func put_on_deck_top(unit: CardInstance) -> void: engine._put_on_deck_top(unit)
func steal_top_discard(opp: int) -> CardInstance: return engine._steal_top_discard(pidx, opp)
func end_turn() -> void: engine._end_turn()
func fire_trap(card: CardInstance) -> void: engine._fire_trap(card)
func set_unit_flag(unit: CardInstance, flag: String) -> void: unit.vars[flag] = true

func request_met(card: CardInstance) -> bool: return engine._request_met(card)

func emit(event: GameEvent) -> void: engine.emit(event)
func request_choice(card: CardInstance, spec, tag: String, asked_player: int = -1) -> void:
	engine._request_choice(card, spec, tag, asked_player if asked_player >= 0 else pidx)
