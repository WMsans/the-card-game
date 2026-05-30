class_name CardView
extends Control

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
@onready var _leader_emblem: TextureRect = $CardSurface/CardViewport/LeaderEmblem

var _instance: CardInstance
var _face_down: bool = false
var base_scale: float = 1.0   # table cards render scaled-down; hover is relative to this
var _dragging: bool = false
var _hovering: bool = false
var _rest_position: Vector2
var _shadow_y_offset: float = 0.0
var _displacement: float = 0.0
var _osc_velocity: float = 0.0
var _last_pos: Vector2
var _interactive: bool = true
var _tween_hover: Tween
var _tween_unhover: Tween
var _tween_grab: Tween

func setup(instance: CardInstance) -> void:
	_instance = instance
	_face_down = false
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
	for n in [_art, _name, _damage, _health, _ticket, _discard, _ability, _flavor, _leader_emblem]:
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

func set_interactive(v: bool) -> void:
	_interactive = v

func set_playable(v: bool) -> void:
	modulate = Color(1, 1, 0.8) if v else Color(0.7, 0.7, 0.7)

func set_attackable(v: bool) -> void:
	modulate = Color(1, 0.9, 0.5) if v else Color(1, 1, 1)

# Resting scale for table cards. Hover/exit tweens animate relative to this so
# a hovered card returns to its table size, not full 1.0.
func set_base_scale(s: float) -> void:
	base_scale = s
	scale = Vector2(s, s)

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
	if not _interactive or _dragging:
		return
	hovered.emit(self)
	z_index = 100
	_hovering = true
	_rest_position = position
	if _tween_hover and _tween_hover.is_running():
		_tween_hover.kill()
	if _tween_unhover and _tween_unhover.is_running():
		_tween_unhover.kill()
	_tween_hover = create_tween()
	_tween_hover.tween_property(self, "scale", Vector2(hover_scale, hover_scale) * base_scale, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	_tween_hover.parallel().tween_property(self, "position:y", _rest_position.y + hover_lift, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _on_mouse_exited() -> void:
	if not _interactive or _dragging:
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
	_tween_unhover.parallel().tween_property(self, "position:y", _rest_position.y, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var tilt_tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tilt_tween.tween_property(_surface.material, "shader_parameter/x_rot", 0.0, 0.5)
	tilt_tween.parallel().tween_property(_surface.material, "shader_parameter/y_rot", 0.0, 0.5)

func _on_gui_input(event: InputEvent) -> void:
	if not _interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			# Grab-relative pivot: keep the card exactly where it was picked up so it
			# doesn't snap-jump to recenter, AND make drag rotation pivot around the
			# cursor. pivot_offset is in local (unscaled) space, so divide the
			# screen-space grab vector by the current scale. The card doesn't jump
			# because moving the pivot to the grab point leaves that point fixed.
			pivot_offset = (get_global_mouse_position() - global_position) / scale
			z_index = 100
			_last_pos = position
			_displacement = 0.0
			_osc_velocity = 0.0
			# Kill hover/unhover tweens so they don't fight drag positioning
			if _tween_hover and _tween_hover.is_running():
				_tween_hover.kill()
			if _tween_unhover and _tween_unhover.is_running():
				_tween_unhover.kill()
			# Snappy grab pop
			if _tween_grab and _tween_grab.is_running():
				_tween_grab.kill()
			_tween_grab = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			_tween_grab.tween_property(self, "scale", Vector2(hover_scale, hover_scale) * base_scale, 0.08)
			drag_started.emit(self)
		else:
			if _dragging:
				_dragging = false
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
				# Satisfying release: elastic scale drop
				var t := create_tween()
				t.tween_property(self, "scale", Vector2.ONE * base_scale, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	elif event is InputEventMouseMotion and not _dragging:
		var lx := remap(event.position.x, 0.0, size.x, 0.0, 1.0)
		var ly := remap(event.position.y, 0.0, size.y, 0.0, 1.0)
		_surface.material.set_shader_parameter("y_rot", rad_to_deg(lerp_angle(-deg_to_rad(angle_max), deg_to_rad(angle_max), lx)))
		_surface.material.set_shader_parameter("x_rot", rad_to_deg(lerp_angle(deg_to_rad(angle_max), -deg_to_rad(angle_max), ly)))

func dissolve() -> Tween:
	var t := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(_visuals.material, "shader_parameter/dissolve_value", 0.0, 0.8).from(1.0)
	t.parallel().tween_property(_shadow, "self_modulate:a", 0.0, 0.8)
	return t
