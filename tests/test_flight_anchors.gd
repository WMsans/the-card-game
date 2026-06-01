extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _spawn() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func test_deck_anchor_is_player_deck_center() -> void:
	var m := _spawn()
	var expected: Vector2 = m._player_deck.global_position + m._player_deck.size * 0.5
	assert_vector(FlightAnchors.of(Enums.Zone.DECK, 0, m)).is_equal_approx(expected, Vector2(1, 1))

func test_discard_anchor_is_player_discard_center() -> void:
	var m := _spawn()
	var expected: Vector2 = m._player_discard.global_position + m._player_discard.size * 0.5
	assert_vector(FlightAnchors.of(Enums.Zone.DISCARD, 0, m)).is_equal_approx(expected, Vector2(1, 1))

func test_opponent_deck_anchor_uses_opp_pile() -> void:
	var m := _spawn()
	var expected: Vector2 = m._opp_deck.global_position + m._opp_deck.size * 0.5
	assert_vector(FlightAnchors.of(Enums.Zone.DECK, 1, m)).is_equal_approx(expected, Vector2(1, 1))

func test_trap_set_resolves_to_trap_pile_anchor() -> void:
	var stub := Control.new()
	add_child(stub)
	auto_free(stub)
	var player_trap := Control.new()
	player_trap.position = Vector2(1660, 280)
	player_trap.size = Vector2(150, 210)
	stub.add_child(player_trap)
	var opp_trap := Control.new()
	opp_trap.position = Vector2(1660, 520)
	opp_trap.size = Vector2(150, 210)
	stub.add_child(opp_trap)
	stub.set_meta("_player_trap", player_trap)
	stub.set_meta("_opp_trap", opp_trap)
	var at := FlightAnchors.of(Enums.Zone.TRAP_SET, 0, stub)
	assert_vector(at).is_equal_approx(player_trap.global_position + player_trap.size * 0.5, Vector2(1, 1))
