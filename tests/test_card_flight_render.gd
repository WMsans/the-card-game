extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"

func _spawn() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(11, "res://src/data/decks/strike.csv", "res://src/data/decks/strike.csv")
	return m

func test_hand_fly_in_starts_new_draw_at_deck_and_face_down() -> void:
	var m := _spawn()
	var hv = m.hand_view
	var hand: Array = m.state.players[0].hand.duplicate()
	var def: CardDefinition = hand[0].definition
	var drawn := CardInstance.new(990001, def)
	hand.append(drawn)
	var from_pos := Vector2(1700, 800)
	var plan := [{"instance_id": 990001, "from": Enums.Zone.DECK, "to": Enums.Zone.HAND,
		"player": 0, "from_pos": from_pos}]
	hv.render(hand, 0, plan)
	var cv: CardView = hv.card_views[990001]
	assert_vector(cv.position).is_equal_approx(from_pos, Vector2(1, 1))
	assert_bool(cv._face_down).is_true()

func test_hand_leaver_to_discard_emits_card_departed() -> void:
	var m := _spawn()
	var hv = m.hand_view
	var hand: Array = m.state.players[0].hand
	hv.render(hand, 0)
	var leaving_id: int = hand[0].instance_id
	var got := {"cv": null, "to": Vector2.ZERO}
	hv.card_departed.connect(func(cv, to): got["cv"] = cv; got["to"] = to)
	var to_pos := Vector2(1700, 600)
	var plan := [{"instance_id": leaving_id, "from": Enums.Zone.HAND, "to": Enums.Zone.DISCARD,
		"player": 0, "to_pos": to_pos}]
	hv.render(hand.slice(1), 0, plan)
	assert_object(got["cv"]).is_not_null()
	assert_vector(got["to"]).is_equal_approx(to_pos, Vector2(1, 1))
	assert_bool(hv.card_views.has(leaving_id)).is_false()

func test_board_leaver_to_discard_emits_card_departed() -> void:
	var m := _spawn()
	var inst: CardInstance = m.state.players[0].hand[0]
	var bv = m.player_board
	bv.render([inst], 0)
	var got := {"cv": null}
	bv.card_departed.connect(func(cv, _to): got["cv"] = cv)
	var plan := [{"instance_id": inst.instance_id, "from": Enums.Zone.BOARD,
		"to": Enums.Zone.DISCARD, "player": 0, "to_pos": Vector2(1700, 600)}]
	bv.render([], 0, plan)
	assert_object(got["cv"]).is_not_null()
	assert_bool(bv.card_views.has(inst.instance_id)).is_false()

func test_face_down_traveler_uses_smaller_scale() -> void:
	var m := _spawn()
	var layer = m._flight
	var cv: CardView = layer.spawn_traveler(null, Vector2(100, 100), Vector2(800, 800))
	assert_bool(cv._face_down).is_true()
	assert_float(cv.base_scale).is_equal_approx(BoardLayout.CARD_SCALE * CardView.FACE_DOWN_SCALE, 0.001)
