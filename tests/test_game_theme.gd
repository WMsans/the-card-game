extends GdUnitTestSuite

const THEME := "res://src/ui/theme/game_theme.tres"

func test_theme_loads_and_styles_buttons() -> void:
	var theme: Theme = load(THEME)
	assert_object(theme).is_instanceof(Theme)
	assert_bool(theme.has_stylebox("normal", "Button")).is_true()
	assert_bool(theme.has_stylebox("hover", "Button")).is_true()
	assert_bool(theme.has_stylebox("pressed", "Button")).is_true()
	assert_bool(theme.has_stylebox("disabled", "Button")).is_true()

func test_theme_styles_panels() -> void:
	var theme: Theme = load(THEME)
	assert_bool(theme.has_stylebox("panel", "Panel")).is_true()