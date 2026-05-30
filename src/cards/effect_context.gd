class_name EffectContext
extends RefCounted

var engine
var pidx: int

func _init(e, p: int) -> void:
	engine = e
	pidx = p

func me() -> int: return pidx
func opponent() -> int: return 1 - pidx
func gs(): return engine.state
func board(p: int) -> Array: return engine.state.players[p].board
func hand(p: int) -> Array: return engine.state.players[p].hand
func discard_pile(p: int) -> Array: return engine.state.players[p].discard
func counters(p: int) -> Dictionary: return engine.state.players[p].turn_counters
func draw(n: int = 1) -> void: engine._draw(pidx, n)
func mill(player: int, n: int) -> void: engine._mill(player, n)
func deal_deck_damage(player: int, n: int) -> void: engine._deck_damage(player, n)
func end_turn() -> void: engine._end_turn()
func request_met(card) -> bool: return engine._request_met(card)
func emit(event) -> void: engine.emit(event)
