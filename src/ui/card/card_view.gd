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
@export var hover_scale: float = 1.12
@export var spring: float = 150.0
@export var damp: float = 10.0
@export var velocity_multiplier: float = 1.0

@onready var _visuals: CanvasGroup = $Visuals
@onready var _shadow: TextureRect = $Shadow
@onready var _frame: TextureRect = $Visuals/Frame
@onready var _art: TextureRect = $Visuals/ArtTexture
@onready var _name: Label = $Visuals/NameLabel
@onready var _damage: Label = $Visuals/DamageLabel
@onready var _health: Label = $Visuals/HealthLabel
@onready var _ticket: Label = $Visuals/TicketLabel
@onready var _discard: Label = $Visuals/DiscardLabel
@onready var _ability: RichTextLabel = $Visuals/AbilityText
@onready var _flavor: Label = $Visuals/FlavorLabel

var _instance: CardInstance
var _face_down: bool = false
var _dragging: bool = false
var _displacement: float = 0.0
var _osc_velocity: float = 0.0
var _last_pos: Vector2
var _interactive: bool = true

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

	_ability.text = _bold_keywords(def.ability_text, def.keywords)
	_flavor.text = def.flavor

func _set_overlays_visible(v: bool) -> void:
	for n in [_art, _name, _damage, _health, _ticket, _discard, _ability, _flavor]:
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

func _process(delta: float) -> void:
	_handle_shadow()
	if _dragging:
		_wobble(delta)

func _handle_shadow() -> void:
	var center := get_viewport_rect().size * 0.5
	var dist := global_position.x - center.x
	_shadow.position.x = lerp(0.0, -sign(dist) * 40.0, abs(dist / maxf(center.x, 1.0)))

func _wobble(delta: float) -> void:
	var velocity := (position - _last_pos) / maxf(delta, 0.0001)
	_last_pos = position
	_osc_velocity += velocity.normalized().x * velocity_multiplier
	var force := -spring * _displacement - damp * _osc_velocity
	_osc_velocity += force * delta
	_displacement += _osc_velocity * delta
	rotation = _displacement

func _on_mouse_entered() -> void:
	if not _interactive or _dragging:
		return
	hovered.emit(self)
	var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	t.tween_property(self, "scale", Vector2(hover_scale, hover_scale), 0.4)

func _on_mouse_exited() -> void:
	if not _interactive:
		return
	unhovered.emit(self)
	_frame.material.set_shader_parameter("x_rot", 0.0)
	_frame.material.set_shader_parameter("y_rot", 0.0)
	var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	t.tween_property(self, "scale", Vector2.ONE, 0.45)

func _on_gui_input(event: InputEvent) -> void:
	if not _interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_last_pos = position
			_displacement = 0.0
			_osc_velocity = 0.0
			drag_started.emit(self)
		else:
			if _dragging:
				_dragging = false
				clicked.emit(self)
				drag_released.emit(self, get_global_mouse_position())
				var t := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
				t.tween_property(self, "rotation", 0.0, 0.3)
	elif event is InputEventMouseMotion and not _dragging:
		var lx := remap(event.position.x, 0.0, size.x, 0.0, 1.0)
		var ly := remap(event.position.y, 0.0, size.y, 0.0, 1.0)
		_frame.material.set_shader_parameter("y_rot", rad_to_deg(lerp_angle(-deg_to_rad(angle_max), deg_to_rad(angle_max), lx)))
		_frame.material.set_shader_parameter("x_rot", rad_to_deg(lerp_angle(deg_to_rad(angle_max), -deg_to_rad(angle_max), ly)))

func dissolve() -> Tween:
	var t := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(_visuals.material, "shader_parameter/dissolve_value", 0.0, 0.8).from(1.0)
	t.parallel().tween_property(_shadow, "self_modulate:a", 0.0, 0.8)
	return t
