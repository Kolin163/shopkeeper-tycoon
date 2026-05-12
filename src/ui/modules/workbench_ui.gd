extends Control
class_name WorkbenchUI

signal changed

@onready var craft_row: HBoxContainer = %CraftRow

var craft_areas: Array[CraftArea] = []
var _signals_connected := false

func _ready() -> void:
	_collect_areas()
	_connect_once()

func _collect_areas() -> void:
	craft_areas.clear()
	for child in craft_row.get_children():
		var a := child as CraftArea
		if a != null:
			craft_areas.append(a)

func _connect_once() -> void:
	if _signals_connected:
		return
	_signals_connected = true
	for a in craft_areas:
		a.changed.connect(func(): changed.emit())

func set_active_tables(count: int) -> void:
	for i in range(craft_areas.size()):
		craft_areas[i].set_enabled(i < count)

func clear_all_silent() -> void:
	for a in craft_areas:
		a.clear_silent()

func take_all_items() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for a in craft_areas:
		out.append_array(a.take_all_items(true))
	return out
