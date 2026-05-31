class_name StagedSelection
extends RefCounted

# Pure selection bookkeeping for in-hand card choices. Holds the staged
# instance_ids in selection order and maps them back to indices in the source
# card list the engine expects. Scene-free and unit-testable.

var source_ids: Array       # instance_ids, index-aligned to the source card list
var min_n: int
var max_n: int
var excluded: Array = []   # instance_ids that cannot be selected but count for indexing
var staged: Array = []      # instance_ids in selection order

func _init(p_source_ids: Array, p_min: int, p_max: int, p_excluded: Array = []) -> void:
	source_ids = p_source_ids
	min_n = p_min
	max_n = p_max
	excluded = p_excluded

# Select / deselect / replace-rightmost. Returns {"added": id|-1, "removed": id|-1}
# so the caller knows which card to fly to center and which to return to hand.
func toggle(id: int) -> Dictionary:
	if excluded.has(id):
		return {"added": -1, "removed": -1}
	if staged.has(id):
		staged.erase(id)
		return {"added": -1, "removed": id}
	if staged.size() < max_n:
		staged.append(id)
		return {"added": id, "removed": -1}
	# At max: drop the rightmost staged card, then add the new one in its place.
	var removed: int = staged[staged.size() - 1]
	staged.remove_at(staged.size() - 1)
	staged.append(id)
	return {"added": id, "removed": removed}

func can_confirm() -> bool:
	return staged.size() >= min_n and staged.size() <= max_n

func to_indices() -> Array:
	var out: Array = []
	for id in staged:
		out.append(source_ids.find(id))
	return out
