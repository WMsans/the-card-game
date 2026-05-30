class_name PlayerState
extends RefCounted

var deck: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var board: Array[CardInstance] = []
var discard: Array[CardInstance] = []
var set_traps: Array[CardInstance] = []
var leader: CardInstance = null
var tickets_total: int = 0
var tickets_tapped: int = 0
var reshuffles_remaining: int = 4
var turns_taken: int = 0
var all_requests_met_this_turn: bool = false
var turn_counters: Dictionary = {}

func _init() -> void:
	reset_turn_counters()

func available_tickets() -> int:
	return tickets_total - tickets_tapped

func reset_turn_counters() -> void:
	all_requests_met_this_turn = false
	turn_counters = {
		"cards_played": 0,
		"cards_discarded": 0,
		"attacks_made": 0,
		"units_died": 0,
	}
