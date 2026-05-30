extends GdUnitTestSuite

func test_choice_spec_select_cards_shape() -> void:
	var spec := ChoiceSpec.select_cards([], 0, 3, "Pick")
	assert_str(spec.ui_shape).is_equal("select_cards")
	assert_int(spec.min_n).is_equal(0)
	assert_int(spec.max_n).is_equal(3)
	assert_str(spec.title).is_equal("Pick")

func test_choice_spec_choose_option_shape() -> void:
	var spec := ChoiceSpec.choose_option(["A", "B"], "Decide")
	assert_str(spec.ui_shape).is_equal("choose_option")
	assert_array(spec.labels).is_equal(["A", "B"])

func test_choice_spec_select_target_shape() -> void:
	var spec := ChoiceSpec.select_target([], 1, 1, "Target")
	assert_str(spec.ui_shape).is_equal("select_target")
	assert_int(spec.min_n).is_equal(1)
	assert_int(spec.max_n).is_equal(1)
	assert_str(spec.title).is_equal("Target")
