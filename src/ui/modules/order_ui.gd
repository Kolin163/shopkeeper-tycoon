extends Control
class_name OrderUI

signal clear_pressed
signal deal_pressed
signal no_deal_pressed

@onready var queue_label: Label = %QueueLabel
@onready var order_label: Label = %OrderLabel
@onready var need_label: Label = %NeedLabel
@onready var patience_bar: ProgressBar = %PatienceBar
@onready var mood_label: Label = %MoodLabel
@onready var status_label: Label = %StatusLabel
@onready var hint_label: Label = %HintLabel

@onready var clear_button: Button = %ClearButton

@onready var bargain_row: HBoxContainer = %BargainRow
@onready var bargain_label: Label = %BargainLabel
@onready var btn_deal: Button = %BtnDeal
@onready var btn_no: Button = %BtnNoDeal

func _ready() -> void:
	clear_button.pressed.connect(func(): clear_pressed.emit())
	btn_deal.pressed.connect(func(): deal_pressed.emit())
	btn_no.pressed.connect(func(): no_deal_pressed.emit())
	bargain_row.visible = false

func set_data(queue_text: String, order_text: String, need_text: String,
		patience_ratio: float, mood_text: String,
		status_text: String, hint_text: String) -> void:
	queue_label.text = queue_text
	order_label.text = order_text
	need_label.text = need_text
	patience_bar.value = clamp(patience_ratio, 0.0, 1.0) * 100.0
	mood_label.text = mood_text
	status_label.text = status_text
	hint_label.text = hint_text

func show_bargain(v: bool, text: String = "") -> void:
	bargain_row.visible = v
	if v and not text.is_empty():
		bargain_label.text = text
