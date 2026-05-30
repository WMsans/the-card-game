class_name CardArt
extends RefCounted

const FRAME_DIR := "res://src/ui/assets/frames/"
const ART_DIR := "res://src/ui/assets/art/"
const BACK := "res://src/ui/assets/frames/back.png"

const _FRAME := {
	Enums.CardType.MINION: "minion.png",
	Enums.CardType.LEADER: "leader.png",
	Enums.CardType.SPELL: "spell.png",
	Enums.CardType.TRAP: "trap.png",
}

static func frame_path(type: int) -> String:
	return FRAME_DIR + _FRAME.get(type, "minion.png")

static func art_path(def: CardDefinition) -> String:
	if def.image == "":
		return ""
	var candidate := ART_DIR + def.image.get_file()
	return candidate if ResourceLoader.exists(candidate) else ""

static var _leader_art_cache := {}

# Art of the leader belonging to the given deck, shown as the emblem on every
# other card in that deck. Empty when the deck or its leader has no art.
static func leader_art_path(deck_color: String) -> String:
	if deck_color == "":
		return ""
	if _leader_art_cache.has(deck_color):
		return _leader_art_cache[deck_color]
	var path := ""
	var deck := "res://src/data/decks/%s.csv" % deck_color
	if ResourceLoader.exists(deck) or FileAccess.file_exists(deck):
		for d in CardDatabase.load_deck(deck, deck_color):
			if d.type == Enums.CardType.LEADER:
				path = art_path(d)
				break
	_leader_art_cache[deck_color] = path
	return path
