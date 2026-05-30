extends GdUnitTestSuite

const CENTER_X := 960.0

func _x(t: Transform2D) -> float:
	return t.origin.x

func test_single_board_card_centered() -> void:
	var t := BoardLayout.slot(Enums.Zone.BOARD, 0, 1, 0)
	assert_float(_x(t)).is_equal_approx(CENTER_X, 1.0)

func test_two_board_cards_symmetric_about_center() -> void:
	var a := BoardLayout.slot(Enums.Zone.BOARD, 0, 2, 0)
	var b := BoardLayout.slot(Enums.Zone.BOARD, 1, 2, 0)
	assert_float(_x(a) + _x(b)).is_equal_approx(2.0 * CENTER_X, 1.0)
	assert_float(_x(a)).is_less(_x(b))

func test_player_board_below_opponent_board() -> void:
	var you := BoardLayout.slot(Enums.Zone.BOARD, 0, 1, 0)
	var opp := BoardLayout.slot(Enums.Zone.BOARD, 0, 1, 1)
	assert_float(you.origin.y).is_greater(opp.origin.y)

func test_tapped_board_card_is_rotated() -> void:
	var untapped := BoardLayout.slot(Enums.Zone.BOARD, 0, 1, 0, false)
	var tapped := BoardLayout.slot(Enums.Zone.BOARD, 0, 1, 0, true)
	assert_float(untapped.get_rotation()).is_equal_approx(0.0, 0.001)
	assert_float(absf(tapped.get_rotation())).is_greater(0.2)

func test_hand_fan_is_ordered_and_centered() -> void:
	var left := BoardLayout.slot(Enums.Zone.HAND, 0, 5, 0)
	var right := BoardLayout.slot(Enums.Zone.HAND, 4, 5, 0)
	assert_float(_x(left)).is_less(_x(right))
	var mid := BoardLayout.slot(Enums.Zone.HAND, 2, 5, 0)
	assert_float(_x(mid)).is_equal_approx(CENTER_X, 40.0)
