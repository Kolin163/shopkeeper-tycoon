extends Control
class_name UIRoot

@export var layout_scene: PackedScene
@export var shelf_scene: PackedScene
@export var workbench_scene: PackedScene
@export var top_bar_scene: PackedScene
@export var order_scene: PackedScene
@export var break_modal_scene: PackedScene
@export var end_modal_scene: PackedScene
@export var upgrades_modal_scene: PackedScene
@export var log_scene: PackedScene

@onready var layout_host: Control = $LayoutHost
@onready var modal_host: Control = $ModalHost

var layout: Control = null
var shelf_ui: ShelfCatalogUI = null
var workbench_ui: WorkbenchUI = null
var top_bar_ui: TopBarUI = null
var order_ui: OrderUI = null
var break_modal: DayBreakModal
var end_modal: EndDayModal
var upgrades_modal: UpgradesModal
var log_ui: LogUI = null

func _ready() -> void:
	_build_layout()
	_build_workspace()
	_build_modals()
	hide_modals()

func _build_layout() -> void:
	for c in layout_host.get_children():
		c.queue_free()

	if layout_scene == null:
		push_warning("UIRoot: layout_scene is null")
		return

	layout = layout_scene.instantiate() as Control
	layout_host.add_child(layout)

func get_slot(slot_name: String) -> Control:
	if layout == null:
		return null
	var p := "%" + slot_name
	if not layout.has_node(p):
		return null
	return layout.get_node(p) as Control

func _build_workspace() -> void:
	var shelf_slot := get_slot("ShelfSlot")
	var workbench_slot := get_slot("WorkbenchSlot")

	if shelf_slot != null:
		for c in shelf_slot.get_children():
			c.queue_free()
	if workbench_slot != null:
		for c in workbench_slot.get_children():
			c.queue_free()

	if shelf_scene != null and shelf_slot != null:
		shelf_ui = shelf_scene.instantiate() as ShelfCatalogUI
		shelf_slot.add_child(shelf_ui)

	if workbench_scene != null and workbench_slot != null:
		workbench_ui = workbench_scene.instantiate() as WorkbenchUI
		workbench_slot.add_child(workbench_ui)
	
	var top_slot := get_slot("TopSlot")
	var order_slot := get_slot("OrderSlot")

	if top_slot != null:
		for c in top_slot.get_children(): c.queue_free()
	if order_slot != null:
		for c in order_slot.get_children(): c.queue_free()

	if top_bar_scene != null and top_slot != null:
		top_bar_ui = top_bar_scene.instantiate() as TopBarUI
		top_slot.add_child(top_bar_ui)

	if order_scene != null and order_slot != null:
		order_ui = order_scene.instantiate() as OrderUI
		order_slot.add_child(order_ui)
	
	var log_slot := get_slot("LogSlot")
	if log_slot != null:
		for c in log_slot.get_children():
			c.queue_free()

	if log_scene != null and log_slot != null:
		log_ui = log_scene.instantiate() as LogUI
		log_slot.add_child(log_ui)

func get_modal_host() -> Control:
	return modal_host

func _build_modals() -> void:
	for c in modal_host.get_children():
		c.queue_free()

	if break_modal_scene != null:
		break_modal = break_modal_scene.instantiate() as DayBreakModal
		modal_host.add_child(break_modal)

	if end_modal_scene != null:
		end_modal = end_modal_scene.instantiate() as EndDayModal
		modal_host.add_child(end_modal)

	if upgrades_modal_scene != null:
		upgrades_modal = upgrades_modal_scene.instantiate() as UpgradesModal
		modal_host.add_child(upgrades_modal)

func hide_modals() -> void:
	if break_modal: break_modal.visible = false
	if end_modal: end_modal.visible = false
	if upgrades_modal: upgrades_modal.visible = false

func show_modal(name: String) -> void:
	hide_modals()
	match name:
		"break":
			if break_modal: break_modal.visible = true
		"end":
			if end_modal: end_modal.visible = true
		"upgrades":
			if upgrades_modal: upgrades_modal.visible = true
