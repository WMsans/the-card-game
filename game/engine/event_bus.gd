class_name EventBus
extends RefCounted

var log: Array[GameEvent] = []
var _listeners: Array[Callable] = []

func subscribe(cb: Callable) -> void:
	_listeners.append(cb)

func publish(event: GameEvent) -> void:
	log.append(event)
	for cb in _listeners:
		cb.call(event)

func events_of_type(t: int) -> Array:
	return log.filter(func(e: GameEvent): return e.type == t)
