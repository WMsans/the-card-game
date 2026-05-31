extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _spawn() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(13, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func test_snapshot_reports_zone_and_player() -> void:
	var m := _spawn()
	var snap: Dictionary = m._snapshot_zones()
	var deck_card: CardInstance = m.state.players[0].deck[0]
	assert_int(snap[deck_card.instance_id]["zone"]).is_equal(Enums.Zone.DECK)
	assert_int(snap[deck_card.instance_id]["player"]).is_equal(0)
	var hand_card: CardInstance = m.state.players[0].hand[0]
	assert_int(snap[hand_card.instance_id]["zone"]).is_equal(Enums.Zone.HAND)

func test_enrich_fills_pile_positions_only() -> void:
	var m := _spawn()
	var raw := [{"instance_id": 1, "from": Enums.Zone.DECK, "to": Enums.Zone.HAND, "player": 0}]
	var plan: Array = m._enrich(raw)
	assert_bool(plan[0].has("from_pos")).is_true()
	assert_bool(plan[0].has("to_pos")).is_false()

func test_spawn_pile_travelers_for_mill() -> void:
	var m := _spawn()
	var iid: int = m.state.players[0].deck[0].instance_id
	var plan: Array = m._enrich([{"instance_id": iid, "from": Enums.Zone.DECK,
		"to": Enums.Zone.DISCARD, "player": 0}])
	m._spawn_pile_travelers(plan)
	assert_int(m._flight.get_child_count()).is_greater(0)

func test_reshuffle_travelers_capped_at_five() -> void:
	var m := _spawn()
	var raw: Array = []
	for k in range(20):
		raw.append({"instance_id": k, "from": Enums.Zone.DISCARD, "to": Enums.Zone.DECK, "player": 0})
	m._spawn_pile_travelers(m._enrich(raw))
	assert_int(m._flight.get_child_count()).is_equal(5)
