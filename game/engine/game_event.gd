class_name GameEvent
extends RefCounted

var type: int
var data: Dictionary

func _init(t: int, d: Dictionary = {}) -> void:
	type = t
	data = d
