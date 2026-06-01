extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"
const STRIKE := "res://src/data/decks/strike.csv"

func _match() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, STRIKE, STRIKE)
	await get_tree().create_timer(0.35).timeout
	m._mulligan.confirmed.emit([])
	await get_tree().create_timer(1.5).timeout
	return m

func _set_trap(m: Node, player: int, iid: int) -> void:
	var d := CardDefinition.new()
	d.type = Enums.CardType.TRAP
	d.name = "Snare"
	var inst := CardInstance.new(iid, d)
	inst.zone = Enums.Zone.TRAP_SET
	m.state.players[player].set_traps.append(inst)

func test_trap_pile_count_reflects_set_traps() -> void:
	var m := await _match()
	_set_trap(m, 0, 501)
	_set_trap(m, 0, 502)
	m.render_all()
	assert_str(m._player_trap.find_child("Count").text).is_equal("2")

func test_clicking_player_trap_opens_overlay() -> void:
	var m := await _match()
	_set_trap(m, 0, 501)
	m.render_all()
	m._on_trap_pile_clicked(0)
	assert_bool(m._pile_overlay.is_open()).is_true()

func test_clicking_empty_trap_pile_does_not_open() -> void:
	var m := await _match()
	m.render_all()
	m._on_trap_pile_clicked(0)
	assert_bool(m._pile_overlay.is_open()).is_false()
