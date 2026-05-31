class_name ChoiceSpec
extends RefCounted

var ui_shape: String
var cards: Array = []
var min_n: int = 0
var max_n: int = 0
var labels: Array = []
var title: String = ""

static func select_cards(card_list: Array, min_n: int, max_n: int, title: String) -> ChoiceSpec:
	var s := ChoiceSpec.new()
	s.ui_shape = "select_cards"
	s.cards = card_list
	s.min_n = min_n
	s.max_n = max_n
	s.title = title
	return s

static func select_target(unit_list: Array, min_n: int, max_n: int, title: String) -> ChoiceSpec:
	var s := ChoiceSpec.new()
	s.ui_shape = "select_target"
	s.cards = unit_list
	s.min_n = min_n
	s.max_n = max_n
	s.title = title
	return s

static func choose_option(labels: Array, title: String) -> ChoiceSpec:
	var s := ChoiceSpec.new()
	s.ui_shape = "choose_option"
	s.labels = labels
	s.title = title
	return s

static func intercept(trap_card, context: String, options: Array) -> ChoiceSpec:
	var s := ChoiceSpec.new()
	s.ui_shape = "intercept"
	s.cards = [trap_card]
	s.labels = options
	s.title = context
	return s
