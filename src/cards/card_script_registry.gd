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
	_register("writing", 1, Shelley.new())
	_register("writing", 2, MelonZombieHulk.new())
	_register("writing", 3, MelonZombieHulk.new())
	_register("writing", OrangeToken.ID, OrangeCard.new())
	_register("writing", 4, CitrusWerewolf.new())
	_register("writing", 5, CitrusWerewolf.new())
	_register("writing", 11, MelonZombie.new())
	_register("writing", 12, MelonZombie.new())
	_register("writing", 13, MercenaryTrader.new())
	_register("writing", 14, MercenaryTrader.new())
	_register("writing", 9, MelonZombieWarlock.new())
	_register("writing", 10, MelonZombieWarlock.new())
	_register("writing", 7, Cultist.new())
	_register("writing", 8, Cultist.new())
	_register("writing", 6, Avatar.new())
	_register("writing", 15, CitrusSacrifice.new())
	_register("writing", 16, CitrusSacrifice.new())
	_register("writing", 17, PainSplit.new())
	_register("writing", 21, Offering.new())

static func get_script_for(deck: String, id: int) -> CardScript:
	_build()
	return _scripts.get(_key(deck, id), _default)
