class_name TransitionPlan
extends RefCounted

static func compute(before: Dictionary, after: Dictionary) -> Array:
	var out: Array = []
	for iid in after:
		if not before.has(iid):
			continue
		var b: Dictionary = before[iid]
		var a: Dictionary = after[iid]
		if b["zone"] != a["zone"]:
			out.append({
				"instance_id": iid,
				"from": b["zone"],
				"to": a["zone"],
				"player": a["player"],
			})
	return out
