class_name FlightAnchors
extends RefCounted

# Screen-space anchor (center) for a flight endpoint. Only piles need a lookup;
# HAND/BOARD endpoints are the card's own slot, supplied by the zone view.
# Callers subtract BoardLayout.CARD_PIVOT to convert this center to a card
# top-left position.

static func of(zone: int, player: int, match_node) -> Vector2:
	var pile = _pile_for(zone, player, match_node)
	if pile != null:
		return pile.global_position + pile.size * 0.5
	# Fallback (HAND/BOARD or unknown) — a sane row center, rarely used.
	var y := BoardLayout.PLAYER_HAND_Y if player == 0 else BoardLayout.OPP_HAND_Y
	return Vector2(BoardLayout.CENTER_X, y)

static func _pile_for(zone: int, player: int, m):
	if zone == Enums.Zone.DECK:
		return m._player_deck if player == 0 else m._opp_deck
	if zone == Enums.Zone.DISCARD:
		return m._player_discard if player == 0 else m._opp_discard
	return null
