class_name CombatDirector
extends RefCounted

const CHAIN_GAP := 0.6
const RAMP_STEP := 0.35
const MAX_SPEED := 2.5
const LUNGE_FRAC := 0.7
const WINDUP_DIST := 26.0
const DEATH_STAGGER := 0.06
const PILE_BUMP_UP := 0.08
const PILE_BUMP_DOWN := 0.12

var anim_speed: float = 1.0
var _last_end: float = -999.0

static func has_attack(events: Array) -> bool:
	for e in events:
		if e.type == Enums.EventType.UNIT_ATTACKED:
			return true
	return false

static func parse_cluster(events: Array) -> Dictionary:
	var c := {
		"attacker": -1, "target_unit": -1, "player": -1,
		"deck_amount": 0, "damaged": [], "died": [],
	}
	for e in events:
		match e.type:
			Enums.EventType.UNIT_ATTACKED:
				c["attacker"] = e.data.get("attacker", -1)
				c["target_unit"] = e.data.get("target_unit", -1)
				c["player"] = e.data.get("player", -1)
			Enums.EventType.UNIT_DAMAGED:
				c["damaged"].append({"id": e.data.get("target", -1), "amount": e.data.get("amount", 0)})
			Enums.EventType.UNIT_DIED:
				c["died"].append(e.data.get("instance", -1))
			Enums.EventType.DECK_DAMAGED:
				c["deck_amount"] = e.data.get("amount", 0)
	return c

static func next_speed(current: float, gap: float) -> float:
	return FeedbackFx.next_speed(current, gap)

func reset_ramp() -> void:
	anim_speed = 1.0

func play(events: Array, m) -> void:
	if not has_attack(events):
		return
	var c := parse_cluster(events)
	var atk: CardView = _find_unit(m, c["attacker"])
	if atk == null:
		return
	anim_speed = next_speed(anim_speed, _now() - _last_end)
	var spd := anim_speed
	var rest_pos: Vector2 = atk._rest_position
	var rest_rot: float = atk._rest_rotation
	var from_center := _center(atk)
	var target_center := _target_center(m, c)
	var to_target := target_center - from_center
	var dir := to_target.normalized()
	atk.z_index = 200

	await CardJuice.windup(atk, rest_pos - dir * WINDUP_DIST, spd).finished
	var frac := 1.0 if c["target_unit"] == -1 else LUNGE_FRAC
	await CardJuice.lunge(atk, rest_pos + to_target * frac, spd).finished
	await m.get_tree().create_timer(CardJuice.HITSTOP / maxf(spd, 0.01)).timeout
	_spawn_numbers(m, c)
	for d in c["damaged"]:
		if d["id"] != c["attacker"]:
			var dv: CardView = _find_unit(m, d["id"])
			if dv != null:
				CardJuice.squash(dv, spd)
	if c["target_unit"] == -1:
		_bump_pile(m, 1 - c["player"], spd)
	await CardJuice.recoil(atk, rest_pos, rest_rot, spd).finished
	atk.z_index = 0
	var stagger := 0.0
	for died_id in c["died"]:
		var cv: CardView = _find_unit(m, died_id)
		if cv != null:
			if stagger > 0.0:
				await m.get_tree().create_timer(stagger).timeout
			await CardJuice.pop(cv, spd).finished
			stagger = DEATH_STAGGER
	_last_end = _now()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _find_unit(m, iid: int) -> CardView:
	if m.player_board.card_views.has(iid):
		return m.player_board.card_views[iid]
	if m.opp_board.card_views.has(iid):
		return m.opp_board.card_views[iid]
	return null

func _center(cv: CardView) -> Vector2:
	return cv.global_position + cv.size * cv.scale * 0.5

func _target_center(m, c: Dictionary) -> Vector2:
	if c["target_unit"] == -1:
		return FlightAnchors.of(Enums.Zone.DECK, 1 - c["player"], m)
	var dv: CardView = _find_unit(m, c["target_unit"])
	if dv != null:
		return _center(dv)
	return FlightAnchors.of(Enums.Zone.DECK, 1 - c["player"], m)

func _spawn_numbers(m, c: Dictionary) -> void:
	var fx: Node = m.get_node("FxLayer")
	if c["target_unit"] == -1:
		var amt: int = c["deck_amount"]
		if amt > 0:
			DamageNumber.spawn(fx, FlightAnchors.of(Enums.Zone.DECK, 1 - c["player"], m), amt, amt >= 4)
		return
	for d in c["damaged"]:
		var cv: CardView = _find_unit(m, d["id"])
		if cv != null and d["amount"] > 0:
			DamageNumber.spawn(fx, _center(cv), d["amount"], d["amount"] >= 4)

func _bump_pile(m, deck_player: int, spd: float) -> void:
	var pile: Control = m._player_deck if deck_player == m.HUMAN else m._opp_deck
	FeedbackFx.bump_pile(pile, spd)
