extends GdUnitTestSuite

const MATCH := "res://src/ui/match/match.tscn"
const STRIKE := "res://src/data/decks/strike.csv"

func _match() -> Node:
	var m: Node = load(MATCH).instantiate()
	add_child(m)
	auto_free(m)
	m.start_game(7, STRIKE, STRIKE)
	await get_tree().create_timer(0.35).timeout
	return m

func _hand_card(m: Node, iid: int, type: int) -> CardView:
	var d := CardDefinition.new()
	d.type = type
	d.name = "Test"
	var inst := CardInstance.new(iid, d)
	inst.zone = Enums.Zone.HAND
	m.hand_view.render([inst], 0)
	await get_tree().create_timer(0.35).timeout
	return m.hand_view.card_views[iid]

func test_spell_feature_moves_card_toward_center() -> void:
	var m := await _match()
	var cv := await _hand_card(m, 301, Enums.CardType.SPELL)
	# Start the beat; sample position partway through the hold.
	m._feature_spell(301, 0)
	await get_tree().create_timer(0.4).timeout
	var center := Vector2(BoardLayout.CENTER_X, BoardLayout.SCREEN.y * 0.5)
	# It should be much closer to center than a hand card's resting Y (~940).
	assert_float(cv.global_position.y).is_less(700.0)
