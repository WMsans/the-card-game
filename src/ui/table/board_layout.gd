class_name BoardLayout
extends RefCounted

const SCREEN := Vector2(1920, 1080)
const CENTER_X := 960.0

const PLAYER_BOARD_Y := 620.0
const OPP_BOARD_Y := 320.0
const PLAYER_HAND_Y := 940.0
const OPP_HAND_Y := 90.0

const BOARD_SLOT_W := 200.0
const HAND_SLOT_W := 150.0
const TAP_ANGLE := deg_to_rad(15.0)
const FAN_ANGLE := deg_to_rad(4.0)

static func _row_x(index: int, count: int, slot_w: float) -> float:
	var total := slot_w * float(count)
	var start := CENTER_X - total * 0.5 + slot_w * 0.5
	return start + slot_w * float(index)

static func slot(zone: int, index: int, count: int, player: int, tapped: bool = false) -> Transform2D:
	var pos := Vector2.ZERO
	var rot := 0.0
	match zone:
		Enums.Zone.BOARD:
			pos = Vector2(_row_x(index, count, BOARD_SLOT_W),
				PLAYER_BOARD_Y if player == 0 else OPP_BOARD_Y)
			rot = TAP_ANGLE if tapped else 0.0
		Enums.Zone.HAND:
			pos = Vector2(_row_x(index, count, HAND_SLOT_W),
				PLAYER_HAND_Y if player == 0 else OPP_HAND_Y)
			var mid := float(count - 1) * 0.5
			rot = (float(index) - mid) * FAN_ANGLE * (1.0 if player == 0 else -1.0)
		_:
			pos = Vector2(CENTER_X, SCREEN.y * 0.5)
	return Transform2D(rot, pos)
