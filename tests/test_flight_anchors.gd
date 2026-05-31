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
