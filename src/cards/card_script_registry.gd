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
	_register("raccoon", 2, Rat.new())
	_register("raccoon", 3, Rat.new())
	_register("raccoon", 4, Opossum.new())
	_register("raccoon", 5, Opossum.new())
	_register("raccoon", 6, Skunk.new())
	_register("raccoon", 7, Skunk.new())
	_register("raccoon", 8, Coyote.new())
	_register("raccoon", 9, Coyote.new())
	_register("raccoon", 10, TrashCannon.new())
	_register("raccoon", 11, TrashCannon.new())
	_register("raccoon", 12, TrashDay.new())
	_register("raccoon", 13, TrashDay.new())
	_register("raccoon", 16, Trashalanche.new())
	_register("raccoon", 17, Trashalanche.new())
	_register("raccoon", 14, TrashToTreasure.new())
	_register("raccoon", 15, TrashToTreasure.new())
	_register("raccoon", 18, GarbageGuard.new())
	_register("raccoon", 19, GarbageGuard.new())

static func get_script_for(deck: String, id: int) -> CardScript:
	_build()
	return _scripts.get(_key(deck, id), _default)
