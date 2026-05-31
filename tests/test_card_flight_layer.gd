extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _spawn() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(5, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func test_spawn_traveler_adds_then_self_frees() -> void:
	var m := _spawn()
	var inst: CardInstance = m.state.players[0].deck[0]
	var cv: CardView = m._flight.spawn_traveler(inst, Vector2(1700, 800), Vector2(1700, 600), 0.0)
	assert_int(m._flight.get_child_count()).is_greater(0)
	await get_tree().create_timer(CardFlight.FLY_TIME + 0.2).timeout
	assert_bool(is_instance_valid(cv)).is_false()

func test_take_leaver_reparents_and_frees() -> void:
	var m := _spawn()
	var hv = m.hand_view
	var hand: Array = m.state.players[0].hand
	hv.render(hand, 0)
	var iid: int = hand[0].instance_id
	var cv: CardView = hv.card_views[iid]
	hv.card_views.erase(iid)   # simulate the zone view releasing ownership
	m._flight.take_leaver(cv, Vector2(1700, 600))
	assert_object(cv.get_parent()).is_same(m._flight)
	await get_tree().create_timer(CardFlight.FLY_TIME + 0.4).timeout
	assert_bool(is_instance_valid(cv)).is_false()
