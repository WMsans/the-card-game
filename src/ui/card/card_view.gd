class_name CardView
extends Control

const FACE_DOWN_SCALE := 0.85
const STAT_NORMAL := Color.WHITE
const STAT_BUFFED := Color(0.4, 1.0, 0.4)
const STAT_DAMAGED := Color(1.0, 0.4, 0.4)

signal hovered(card_view: CardView)
signal unhovered(card_view: CardView)
signal drag_started(card_view: CardView)
signal drag_released(card_view: CardView, at: Vector2)
signal clicked(card_view: CardView)

@export var angle_max: float = 12.0
@export var hover_scale: float = 1.8
@export var hover_lift: float = -160.0
@export var hover_shadow_offset: Vector2 = Vector2(8.0, 16.0)
@export var spring: float = 800.0
@export var damp: float = 8.0
@export var velocity_multiplier: float = 1.0

@onready var _surface: SubViewportContainer = $CardSurface
@onready var _visuals: CanvasGroup = $CardSurface/CardViewport/Visuals
@onready var _shadow: TextureRect = $Shadow
@onready var _frame: TextureRect = $CardSurface/CardViewport/Visuals/Frame
@onready var _art: TextureRect = $CardSurface/CardViewport/Visuals/ArtTexture
@onready var _name: Label = $CardSurface/CardViewport/Visuals/NameLabel
@onready var _damage: Label = $CardSurface/CardViewport/Visuals/DamageLabel
@onready var _health: Label = $CardSurface/CardViewport/Visuals/HealthLabel
@onready var _ticket: Label = $CardSurface/CardViewport/Visuals/TicketLabel
@onready var _discard: Label = $CardSurface/CardViewport/Visuals/DiscardLabel
@onready var _ability: RichTextLabel = $CardSurface/CardViewport/Visuals/AbilityText
@onready var _flavor: Label = $CardSurface/CardViewport/Visuals/FlavorLabel
@onready var _credit: Label = $CardSurface/CardViewport/Visuals/CreditLabel
@onready var _leader_emblem: TextureRect = $CardSurface/CardViewport/LeaderEmblem
@onready var _highlight: CardHighlight = $Highlight

var _instance: CardInstance
var _face_down: bool = false
var _consumed: bool = false
var base_scale: float = 1.0   # table cards render scaled-down; hover is relative to this
static var _active_drag: CardView = null

var _dragging: bool = false
var _hovering: bool = false
var _rest_position: Vector2
var _rest_rotation: float
# True once the slot is known authoritatively (set by the layout, or captured on
# the first hover for static panels). Hover/release animate to this fixed value
# instead of re-reading the live, possibly mid-tween, position.
var _rest_set: bool = false
var _shadow_y_offset: float = 0.0
var _displacement: float = 0.0
var _osc_velocity: float = 0.0
var _last_pos: Vector2
var _interactive: bool = true
var select_only: bool = false
var lift_on_hover: bool = false
var _tween_hover: Tween
var _tween_unhover: Tween
var _tween_grab: Tween
var _tween_release: Tween
var _tween_tilt: Tween

func setup(instance: CardInstance) -> void:
	_instance = instance
	_face_down = false
	_consumed = false
	_refresh()

func set_face_down(value: bool) -> void:
	_face_down = value
	_refresh()

func _refresh() -> void:
	if _instance == null:
		return
	if _face_down:
		_frame.texture = load(CardArt.BACK)
		_set_overlays_visible(false)
		return
	var def := _instance.definition
	_frame.texture = load(CardArt.frame_path(def.type))
	_set_overlays_visible(true)

	_name.text = def.name
	_ticket.text = str(def.ticket_cost)

	var art := CardArt.art_path(def)
	_art.visible = art != ""
	if art != "":
		_art.texture = load(art)

	var is_unit := def.type == Enums.CardType.MINION or def.type == Enums.CardType.LEADER
	_damage.visible = is_unit
	_health.visible = is_unit
	_damage.text = str(_instance.current_damage)
	_health.text = str(_instance.current_health)
	_damage.modulate = _stat_color(_instance.current_damage, def.base_damage)
	_health.modulate = _stat_color(_instance.current_health, def.base_health)

	_discard.visible = def.type == Enums.CardType.LEADER
	_discard.text = str(def.alt_discard_cost)

	_refresh_leader_emblem(def)

	_ability.text = _bold_keywords(def.ability_text, def.keywords)
	_flavor.text = def.flavor
	_credit.text = "Illustration by %s" % def.credit if def.credit != "" else ""
	_credit.visible = def.credit != ""

func _refresh_leader_emblem(def: CardDefinition) -> void:
	# The leader's portrait marks which deck a Minion/Spell/Trap belongs to;
	# the Leader card itself doesn't carry its own emblem.
	var emblem := ""
	if def.type != Enums.CardType.LEADER:
		emblem = CardArt.leader_art_path(def.deck_color)
	_leader_emblem.visible = emblem != ""
	if emblem != "":
		_leader_emblem.texture = load(emblem)

func _set_overlays_visible(v: bool) -> void:
	for n in [_art, _name, _damage, _health, _ticket, _discard, _ability, _flavor, _credit, _leader_emblem]:
		n.visible = v

func _stat_color(current: int, base: int) -> Color:
	if current > base:
		return STAT_BUFFED
	if current < base:
		return STAT_DAMAGED
	return STAT_NORMAL

func _bold_keywords(text: String, keywords: Array[String]) -> String:
	var out := text
	for kw in keywords:
		out = out.replace(kw, "[b]%s[/b]" % kw)
	return out

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

func mark_played() -> void:
	_consumed = true

func set_interactive(v: bool) -> void:
	_interactive = v

# Pin the card for a scripted feature/flight (e.g. lift-to-center). Stops it from
# responding to hover and kills any in-flight hover/unhover tweens, which would
# otherwise animate position:y back to the hand rest slot and drag the card out
# of center mid-beat.
func begin_feature() -> void:
	_interactive = false
	_hovering = false
	z_index = 0
	for tw in [_tween_hover, _tween_unhover, _tween_tilt]:
		if tw and tw.is_running():
			tw.kill()

func set_highlight(state: int) -> void:
	_highlight.set_state(state)

func set_playable(v: bool) -> void:
	set_highlight(CardHighlight.State.PLAYABLE if v else CardHighlight.State.NONE)

func set_attackable(v: bool) -> void:
	set_highlight(CardHighlight.State.ATTACKABLE if v else CardHighlight.State.NONE)

# Resting scale for table cards. Hover/exit tweens animate relative to this so
# a hovered card returns to its table size, not full 1.0.
func set_base_scale(s: float) -> void:
	base_scale = s
	scale = Vector2(s, s)

# Authoritative slot, supplied by the layout (hand/board). Hover, unhover, and
# release all animate back to this — never to a value sampled from the live
# `position`, which may be mid-tween and would otherwise let the card ratchet
# away from its slot under rapid hover/click.
func set_rest(pos: Vector2, rot: float) -> void:
	_rest_position = pos
	_rest_rotation = rot
	_rest_set = true

func _process(delta: float) -> void:
	_handle_shadow(delta)
	if _dragging:
		# Exact, same-frame follow: the card stays pinned under the cursor at the
		# exact point it was grabbed (no recenter snap). This is what reads as snappy.
		# pivot_offset is the grab point, so keeping it under the mouse also makes the
		# wobble rotation spin around the cursor instead of the top-left corner.
		global_position = get_global_mouse_position() - pivot_offset
		_wobble(delta)

func _handle_shadow(delta: float) -> void:
	var center := get_viewport_rect().size * 0.5
	var dist := global_position.x - center.x
	_shadow.position.x = lerp(0.0, -sign(dist) * 40.0, abs(dist / maxf(center.x, 1.0)))
	var target_y := hover_shadow_offset.y if _hovering else 0.0
	_shadow_y_offset = lerpf(_shadow_y_offset, target_y, 1.0 - exp(-12.0 * delta))
	_shadow.position.y = _shadow_y_offset
	if _hovering:
		_shadow.position.x += hover_shadow_offset.x

func _wobble(delta: float) -> void:
	# Lean the card into the drag motion. The kick is proportional to actual
	# horizontal speed (clamped) so fast flicks lean hard and slow drags stay calm,
	# instead of a constant nudge that feels mushy.
	var velocity := (position - _last_pos) / maxf(delta, 0.0001)
	_last_pos = position
	_osc_velocity += clampf(velocity.x, -2400.0, 2400.0) * 0.00035 * velocity_multiplier
	var force := -spring * _displacement - damp * _osc_velocity
	_osc_velocity += force * delta
	_displacement += _osc_velocity * delta
	_displacement = clampf(_displacement, -0.4, 0.4)
	rotation = _displacement

func _on_mouse_entered() -> void:
	if not _interactive or _dragging or _active_drag != null:
		return
	hovered.emit(self)
	z_index = 100
	_hovering = true
	# Static panels (gallery/overlays) never call set_rest; capture their stable
	# slot once on first hover. Animated layouts (hand/board) set it explicitly.
	if not _rest_set:
		_rest_position = position
		_rest_rotation = rotation
		_rest_set = true
	if _tween_hover and _tween_hover.is_running():
		_tween_hover.kill()
	if _tween_unhover and _tween_unhover.is_running():
		_tween_unhover.kill()
	if _tween_tilt and _tween_tilt.is_running():
		_tween_tilt.kill()
	_tween_hover = create_tween()
	_tween_hover.tween_property(self, "scale", Vector2(hover_scale, hover_scale) * base_scale, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	if lift_on_hover:
		_tween_hover.parallel().tween_property(self, "position:y", _rest_position.y + hover_lift, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _on_mouse_exited() -> void:
	if not _interactive or _dragging or _active_drag != null:
		return
	unhovered.emit(self)
	z_index = 0
	_hovering = false
	if _tween_hover and _tween_hover.is_running():
		_tween_hover.kill()
	if _tween_unhover and _tween_unhover.is_running():
		_tween_unhover.kill()
	_tween_unhover = create_tween()
	_tween_unhover.tween_property(self, "scale", Vector2.ONE * base_scale, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	if lift_on_hover:
		_tween_unhover.parallel().tween_property(self, "position:y", _rest_position.y, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if _tween_tilt and _tween_tilt.is_running():
		_tween_tilt.kill()
	_tween_tilt = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween_tilt.tween_property(_surface.material, "shader_parameter/x_rot", 0.0, 0.5)
	_tween_tilt.parallel().tween_property(_surface.material, "shader_parameter/y_rot", 0.0, 0.5)

func _on_gui_input(event: InputEvent) -> void:
	if not _interactive:
		return
	if select_only and event is InputEventMouseButton:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_consumed = false
			_active_drag = self
			# Grab-relative pivot: keep the card exactly where it was picked up so it
			# doesn't snap-jump to recenter, AND make drag rotation pivot around the
			# cursor. pivot_offset is in local (unscaled) space, so divide the
			# screen-space grab vector by the current scale. The card doesn't jump
			# because moving the pivot to the grab point leaves that point fixed.
			pivot_offset = (get_global_mouse_position() - global_position) / scale
			z_index = 100
			# _rest_position / _rest_rotation are the authoritative slot from the
			# layout (set_rest); never recapture them from the live, lifted/wobbling
			# transform here or the release tween would land the card in the wrong spot.
			_last_pos = position
			_displacement = 0.0
			_osc_velocity = 0.0
			# Kill all competing tweens so they don't fight drag positioning
			if _tween_hover and _tween_hover.is_running():
				_tween_hover.kill()
			if _tween_unhover and _tween_unhover.is_running():
				_tween_unhover.kill()
			if _tween_release and _tween_release.is_running():
				_tween_release.kill()
			if _tween_tilt and _tween_tilt.is_running():
				_tween_tilt.kill()
			# Snappy grab pop
			if _tween_grab and _tween_grab.is_running():
				_tween_grab.kill()
			_tween_grab = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			_tween_grab.tween_property(self, "scale", Vector2(hover_scale, hover_scale) * base_scale, 0.08)
			drag_started.emit(self)
		else:
			if _dragging:
				_dragging = false
				_active_drag = null
				_hovering = false
				z_index = 0
				# Restore the center pivot for hover/hand layout, compensating
				# position so the card doesn't jump when the rotation center moves.
				var center := size * 0.5
				global_position += (Vector2.ONE - scale) * (pivot_offset - center)
				pivot_offset = center
				clicked.emit(self)
				drag_released.emit(self, get_global_mouse_position())
				if _tween_grab and _tween_grab.is_running():
					_tween_grab.kill()
				# Satisfying release: elastic scale drop + return to rest
				if _tween_release and _tween_release.is_running():
					_tween_release.kill()
				if not _consumed:
					_tween_release = create_tween()
					_tween_release.tween_property(self, "scale", Vector2.ONE * base_scale, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
					_tween_release.parallel().tween_property(self, "position", _rest_position, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
					_tween_release.parallel().tween_property(self, "rotation", _rest_rotation, 0.25).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	elif event is InputEventMouseMotion and _hovering and _active_drag == null:
		# Only tilt while this card is the active hover. Without the _active_drag /
		# _hovering guard, moving over a card while another is dragged would set the
		# shader tilt but neither mouse_entered nor mouse_exited (both guarded) would
		# ever reset it, leaving the card stuck in a tilted 3D rotation.
		var lx := remap(event.position.x, 0.0, size.x, 0.0, 1.0)
		var ly := remap(event.position.y, 0.0, size.y, 0.0, 1.0)
		_surface.material.set_shader_parameter("y_rot", rad_to_deg(lerp_angle(-deg_to_rad(angle_max), deg_to_rad(angle_max), lx)))
		_surface.material.set_shader_parameter("x_rot", rad_to_deg(lerp_angle(deg_to_rad(angle_max), -deg_to_rad(angle_max), ly)))

func dissolve() -> Tween:
	var t := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(_visuals.material, "shader_parameter/dissolve_value", 0.0, 0.8).from(1.0)
	t.parallel().tween_property(_shadow, "self_modulate:a", 0.0, 0.8)
	return t

func flip_to_face_up() -> Tween:
	_surface.pivot_offset = _surface.size * 0.5
	var t := _surface.create_tween()
	t.tween_property(_surface, "scale:x", 0.0, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): set_face_down(false))
	t.tween_property(_surface, "scale:x", 1.0, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return t

func flip_to_face_down() -> Tween:
	_surface.pivot_offset = _surface.size * 0.5
	var target := Vector2(base_scale, base_scale) * FACE_DOWN_SCALE
	var t := _surface.create_tween()
	t.tween_property(_surface, "scale:x", 0.0, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): set_face_down(true))
	t.tween_property(_surface, "scale:x", 1.0, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "scale", target, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return t
