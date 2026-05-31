extends CanvasLayer

signal confirmed(indices: Array)
signal minimize_requested

const THEME := preload("res://src/ui/theme/game_theme.tres")
const STAGE_SLOT_W := 180.0
const STAGE_Y := 500.0

@onready var _title: Label = $Title
@onready var _confirm: Button = $Confirm

var _hand_view = null
var _sel: StagedSelection = null
var _handlers: Dictionary = {}
var _locked: Array = []
var _active: bool = false

func _ready() -> void:
	_title.theme = THEME
	_confirm.theme = THEME
	_confirm.pressed.connect(_confirm_pressed)
	JuicyButton.apply(_confirm)
	var _min_btn: Button = $MinimizeButton
	JuicyButton.apply(_min_btn)
	_min_btn.pressed.connect(func(): minimize_requested.emit())

func start(hand_view, source_cards: Array, min_n: int, max_n: int, title: String, excluded_ids: Array = []) -> void:
	if not is_node_ready():
		await ready
	if _active:
		return
	_hand_view = hand_view
	var source_ids: Array = []
	for c in source_cards:
		source_ids.append(c.instance_id)
	_sel = StagedSelection.new(source_ids, min_n, max_n, excluded_ids)
	_title.text = title
	_locked = []
	for id in _hand_view.card_views.keys():
		var cv: CardView = _hand_view.card_views[id]
		cv.select_only = true
		_locked.append(id)
	_handlers = {}
	for id in source_ids:
		if excluded_ids.has(id):
			continue
		var cv: CardView = _hand_view.card_views.get(id)
		if cv == null:
			continue
		var cb := _make_click_handler(id)
		cv.gui_input.connect(cb)
		_handlers[id] = cb
	_active = true
	visible = true
	_confirm.disabled = not _sel.can_confirm()

func _make_click_handler(id: int) -> Callable:
	return func(e):
		if e is InputEventMouseButton and e.pressed:
			_on_card_clicked(id)

func _on_card_clicked(id: int) -> void:
	if _sel == null:
		return
	_sel.toggle(id)
	_hand_view.set_choice_excluded(_sel.staged)
	_restage()
	_confirm.disabled = not _sel.can_confirm()

func _restage() -> void:
	var n := _sel.staged.size()
	for i in range(n):
		var cv: CardView = _hand_view.card_views.get(_sel.staged[i])
		if cv == null:
			continue
		var pos := Vector2(_stage_x(i, n), STAGE_Y) - BoardLayout.CARD_PIVOT
		cv.z_index = 50 + i
		cv.set_rest(pos, 0.0)
		CardFlight.move_to(cv, pos, 0.0, float(i) * CardFlight.STAGGER)

func _stage_x(index: int, count: int) -> float:
	var total := STAGE_SLOT_W * float(count)
	var start := BoardLayout.CENTER_X - total * 0.5 + STAGE_SLOT_W * 0.5
	return start + STAGE_SLOT_W * float(index)

func _confirm_pressed() -> void:
	if _sel == null or not _sel.can_confirm():
		return
	var indices := _sel.to_indices()
	_deactivate()
	confirmed.emit(indices)

func _deactivate() -> void:
	for id in _handlers:
		var cv: CardView = _hand_view.card_views.get(id)
		if cv != null and cv.gui_input.is_connected(_handlers[id]):
			cv.gui_input.disconnect(_handlers[id])
	_handlers.clear()
	for id in _locked:
		var cv: CardView = _hand_view.card_views.get(id)
		if cv != null:
			cv.select_only = false
	_locked.clear()
	if _hand_view != null:
		_hand_view.set_choice_excluded([])
	_sel = null
	_active = false
	visible = false

func get_animatable_nodes() -> Array[Node]:
	return [_title, _confirm]

func get_dim_node() -> Control:
	return null
