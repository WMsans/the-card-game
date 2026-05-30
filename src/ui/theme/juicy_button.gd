class_name JuicyButton
extends RefCounted

const HOVER_SCALE := 1.08
const PRESS_SCALE := 0.92
const TILT_DEG := 2.5
const HOVER_TIME := 0.25
const SETTLE_TIME := 0.4
const PRESS_TIME := 0.08

static func apply(btn: Button) -> void:
	btn.pivot_offset = btn.size * 0.5
	btn.resized.connect(func() -> void: btn.pivot_offset = btn.size * 0.5)
	var st := {"tween": null}
	var retween := func() -> Tween:
		if st["tween"] != null and st["tween"].is_running():
			st["tween"].kill()
		st["tween"] = btn.create_tween().set_ease(Tween.EASE_OUT)
		return st["tween"]
	var _on_mouse_entered := func() -> void:
		if btn.disabled: return
		var t: Tween = retween.call().set_trans(Tween.TRANS_BACK)
		t.tween_property(btn, "scale", Vector2.ONE * HOVER_SCALE, HOVER_TIME)
		t.parallel().tween_property(btn, "rotation", deg_to_rad(TILT_DEG), HOVER_TIME)
	var _on_mouse_exited := func() -> void:
		var t: Tween = retween.call().set_trans(Tween.TRANS_ELASTIC)
		t.tween_property(btn, "scale", Vector2.ONE, SETTLE_TIME)
		t.parallel().tween_property(btn, "rotation", 0.0, SETTLE_TIME)
	var _on_button_down := func() -> void:
		if btn.disabled: return
		var t: Tween = retween.call().set_trans(Tween.TRANS_BACK)
		t.tween_property(btn, "scale", Vector2.ONE * PRESS_SCALE, PRESS_TIME)
		t.parallel().tween_property(btn, "rotation", deg_to_rad(-TILT_DEG), PRESS_TIME)
	var _on_button_up := func() -> void:
		if btn.disabled: return
		var target := HOVER_SCALE if btn.is_hovered() else 1.0
		var t: Tween = retween.call().set_trans(Tween.TRANS_ELASTIC)
		t.tween_property(btn, "scale", Vector2.ONE * target, SETTLE_TIME)
		t.parallel().tween_property(btn, "rotation", 0.0, SETTLE_TIME)
	btn.mouse_entered.connect(_on_mouse_entered)
	btn.mouse_exited.connect(_on_mouse_exited)
	btn.button_down.connect(_on_button_down)
	btn.button_up.connect(_on_button_up)