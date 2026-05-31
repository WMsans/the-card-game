class_name CardScriptRegistry
extends RefCounted

static var _default := DefaultCard.new()
static var _scripts: Dictionary = {}      # "deck:id" -> CardScript
static var _built: bool = false

static func _key(deck: String, id: int) -> String:
	return "%s:%d" % [deck.to_lower(), id]

static func _register(deck: String, id: int, script: CardScript) -> void:
	_scripts[_key(deck, id)] = script

static func _build() -> void:
	if _built:
		return
	_built = true
	_register("strike", 1, BattleBjorn.new())
	_register("strike", 2, StrikeRequestForm.new())
	_register("strike", 3, StrikeRequestForm.new())
	_register("strike", 4, PriorityRaise.new())
	_register("strike", 5, BountyStriker.new())
	_register("strike", 6, BountyStriker.new())
	_register("strike", 7, RedAlien.new())
	_register("strike", 8, HeadphonesGhost.new())
	_register("strike", 9, GrayAlien.new())
	_register("strike", 10, CactusGuy.new())
	_register("strike", 11, RequestSlacker.new())
	_register("strike", 12, RequestSlacker.new())
	_register("strike", 13, Overstriker.new())
	_register("strike", 14, Overstriker.new())
	_register("strike", 15, RequestBoard.new())
	_register("strike", 16, RequestBoard.new())
	_register("strike", 17, BjornHammer.new())
	_register("strike", 18, BjornHammer.new())
	_register("strike", 19, WrongMascot.new())
	_register("strike", 20, WrongMascot.new())
	_register("strike", 21, StrikeSocial.new())
	_register("writing", OrangeToken.ID, OrangeCard.new())
	_register("audio", 1, Plop.new())
	_register("audio", 2, QuarterNote.new())
	_register("audio", 3, QuarterNote.new())
	_register("audio", 4, HalfNote.new())
	_register("audio", 5, HalfNote.new())
	_register("audio", 6, EighthNote.new())
	_register("audio", 7, EighthNote.new())
	_register("audio", 8, SixteenthNote.new())
	_register("audio", 9, SixteenthNote.new())
	_register("audio", 10, WholeNote.new())
	_register("audio", 11, WholeNote.new())
	_register("audio", 12, TrebleClef.new())
	_register("audio", 13, BassClef.new())
	_register("audio", 14, HarmonizeSpell.new())
	_register("audio", 15, HarmonizeSpell.new())
	_register("audio", 16, Staccato.new())
	_register("audio", 17, Staccato.new())
	_register("audio", 18, Legato.new())
	_register("audio", 19, Legato.new())
	_register("audio", 20, Rest.new())
	_register("audio", 21, Rest.new())

static func get_script_for(deck: String, id: int) -> CardScript:
	_build()
	return _scripts.get(_key(deck, id), _default)
