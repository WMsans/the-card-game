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
