class_name CardView
extends Control

const STAT_NORMAL := Color.WHITE
const STAT_BUFFED := Color(0.4, 1.0, 0.4)
const STAT_DAMAGED := Color(1.0, 0.4, 0.4)

@onready var _frame: TextureRect = $Frame
@onready var _art: TextureRect = $ArtTexture
@onready var _name: Label = $NameLabel
@onready var _damage: Label = $DamageLabel
@onready var _health: Label = $HealthLabel
@onready var _ticket: Label = $TicketLabel
@onready var _discard: Label = $DiscardLabel
@onready var _ability: RichTextLabel = $AbilityText
@onready var _flavor: Label = $FlavorLabel

var _instance: CardInstance
var _face_down: bool = false

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
