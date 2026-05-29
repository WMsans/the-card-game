class_name PendingChoice
extends RefCounted

var kind: String
var player: int
var data: Dictionary

func _init(k: String, p: int, d: Dictionary = {}) -> void:
	kind = k
	player = p
	data = d
