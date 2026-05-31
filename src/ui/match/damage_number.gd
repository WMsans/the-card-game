class_name DamageNumber
extends Node2D

const GRAVITY := 1400.0
const LIFETIME := 0.6
const SMALL_TINT := Color(1.0, 0.30, 0.30)
const BIG_TINT := Color(1.0, 0.85, 0.20)

var _vel: Vector2 = Vector2.ZERO
var _life: float = LIFETIME

static func spawn(parent: Node, at: Vector2, amount: int, big: bool = false) -> DamageNumber:
	var dn := DamageNumber.new()
	parent.add_child(dn)
	dn.global_position = at
	dn._setup(amount, big)
	return dn

func _setup(amount: int, big: bool) -> void:
	var label := Label.new()
	label.text = "-%d" % amount
	label.modulate = BIG_TINT if big else SMALL_TINT
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	var s := 1.5 if big else 1.0
	scale = Vector2(1.4, 1.4) * s
	_vel = Vector2(randf_range(-90.0, 90.0), randf_range(-260.0, -180.0))
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(s, s), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	_vel.y += GRAVITY * delta
	position += _vel * delta
	rotation += delta * 2.0
	_life -= delta
	modulate.a = clampf(_life / LIFETIME, 0.0, 1.0)
	if _life <= 0.0:
		queue_free()
