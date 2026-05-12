extends Control
class_name EndDayModal

signal continue_pressed

@onready var end_summary_label: Label = %EndSummaryLabel
@onready var continue_button: Button = %ToBreakButton

func _ready() -> void:
	continue_button.pressed.connect(func(): continue_pressed.emit())

func set_summary(text: String) -> void:
	end_summary_label.text = text
