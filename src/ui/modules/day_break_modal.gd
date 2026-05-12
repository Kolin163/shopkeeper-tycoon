extends Control
class_name DayBreakModal

signal start_day_pressed
signal upgrades_pressed

@onready var start_day_button: Button = %StartDayButton


func _ready() -> void:
	start_day_button.pressed.connect(func(): start_day_pressed.emit())
