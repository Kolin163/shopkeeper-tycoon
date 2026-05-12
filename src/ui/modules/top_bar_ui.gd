extends Control
class_name TopBarUI

signal restock_pressed
signal upgrades_pressed

@onready var day_label: Label = %DayLabel
@onready var day_timer_label: Label = %DayTimerLabel
@onready var day_mod_label: Label = %DayModLabel

@onready var gold_label: Label = %GoldLabel
@onready var combo_label: Label = %ComboLabel
@onready var level_label: Label = %LevelLabel
@onready var preps_label: Label = %PrepsLabel

@onready var restock_button: Button = %RestockButton
@onready var upgrades_button: Button = %UpgradesButton

func _ready() -> void:
	restock_button.pressed.connect(func(): restock_pressed.emit())
	upgrades_button.pressed.connect(func(): upgrades_pressed.emit())

func set_data(day_index: int, day_time_left: float, day_mod_text: String,
		gold: int, combo: int, level: int, preps_count: int) -> void:
	day_label.text = "Day: %d" % day_index

	var t = max(0.0, day_time_left)
	var sec := int(t) % 60
	var min := int(t) / 60
	day_timer_label.text = "%02d:%02d" % [min, sec]

	day_mod_label.text = day_mod_text

	gold_label.text = "Gold: %d" % gold
	combo_label.text = "Combo: %d" % combo
	level_label.text = "Level: %d" % level
	preps_label.text = "Preps: %d" % preps_count
