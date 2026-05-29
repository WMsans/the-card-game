shader_type canvas_item;

// Masks a TextureRect to a centered circle, discarding anything outside it.
// Used to fit square leader art into the round emblem on the card frame.
void fragment() {
	if (length(UV - vec2(0.5)) > 0.5) {
		discard;
	}
}
