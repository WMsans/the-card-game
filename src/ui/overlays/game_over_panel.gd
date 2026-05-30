extends CanvasLayer

signal play_again
signal quit

@onready var _label: Label = $Panel/ResultLabel

func _ready() -> void:
	$Panel/PlayAgain.pressed.connect(func(): play_again.emit())
	$Panel/Quit.pressed.connect(func(): quit.emit())
	$Panel.theme = preload("res://src/ui/theme/game_theme.tres")
	JuicyButton.apply($Panel/PlayAgain)
	JuicyButton.apply($Panel/Quit)

func show_result(winner: int, human: int) -> void:
	if not is_node_ready(): await ready
	_label.text = "You Win" if winner == human else "You Lose"
	visible = true