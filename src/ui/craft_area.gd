extends PanelContainer
class_name CraftArea

signal changed

@onready var margin: MarginContainer = $MarginContainer
@onready var body: Control = $MarginContainer/Body
@onready var hint_label: Label = $MarginContainer/Body/HintLabel
@onready var items_flow: Control = $MarginContainer/Body/ItemsFlow

var items: Array[ItemDef] = []
var enabled: bool = true
var _sb_normal: StyleBoxFlat
var _sb_hot: StyleBoxFlat


func _ready() -> void:
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	items_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_styles()
	_set_hot(false)
	_redraw()


func _build_styles() -> void:
	_sb_normal = StyleBoxFlat.new()
	_sb_normal.bg_color = Color(0.12, 0.12, 0.12, 1.0)
	_sb_normal.border_width_left = 3
	_sb_normal.border_width_top = 3
	_sb_normal.border_width_right = 3
	_sb_normal.border_width_bottom = 3
	_sb_normal.border_color = Color(0.35, 0.35, 0.35, 1.0)

	_sb_hot = _sb_normal.duplicate()
	_sb_hot.border_color = Color(1.0, 0.8, 0.2, 1.0)
	_sb_hot.bg_color = Color(0.16, 0.14, 0.08, 1.0)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return enabled and (data is ItemDef)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var it := data as ItemDef
	if it == null:
		return
	if not enabled:
		return
	
	if DataManager.is_stocked(it.id):
		if not DataManager.spend_stock(it.id):
			return
	
	items.append(it)
	_auto_craft()
	_redraw()
	changed.emit()


func clear() -> void:
	if items.is_empty():
		return
	items.clear()
	_redraw()
	changed.emit()


func get_items() -> Array[ItemDef]:
	return items.duplicate()


func has_item(id: StringName) -> bool:
	for it in items:
		if it.id == id:
			return true
	return false


func remove_one(id: StringName, emit_change: bool = true) -> bool:
	for i in range(items.size()):
		if items[i].id == id:
			items.remove_at(i)
			_redraw()
			if emit_change:
				changed.emit()
			return true
	return false

func set_enabled(v: bool) -> void:
	if enabled == v:
		return
	enabled = v
	visible = v
	mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
	if not v:
		clear_silent()

func clear_silent() -> void:
	if items.is_empty():
		return
	items.clear()
	_redraw()

func take_all_items(silent: bool = true) -> Array[ItemDef]:
	var out := items.duplicate()
	items.clear()
	_redraw()
	if not silent:
		changed.emit()
	return out

func put_items(arr: Array[ItemDef], silent: bool = true) -> void:
	for it in arr:
		if it != null:
			items.append(it)
	_redraw()
	if not silent:
		changed.emit()

func _redraw() -> void:
	for c in items_flow.get_children():
		c.queue_free()

	for it in items:
		items_flow.add_child(_make_item_view(it))

	hint_label.visible = items.is_empty()


func _make_item_view(it: ItemDef) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(48, 48)

	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.15, 0.15, 0.15, 1.0)
	root.add_child(bg)

	if it.icon != null:
		var ic := TextureRect.new()
		ic.anchor_right = 1.0
		ic.anchor_bottom = 1.0
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture = it.icon
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(ic)
	else:
		var l := Label.new()
		l.anchor_right = 1.0
		l.anchor_bottom = 1.0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.text = _safe_name(it)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(l)

	return root


func _safe_name(it: ItemDef) -> String:
	if it == null:
		return "?"
	var key := String(it.name_key)
	var s := tr(key)
	return s if s != key else String(it.id)


func _notification(what: int) -> void:
	if what == Node.NOTIFICATION_DRAG_BEGIN:
		var data = get_viewport().gui_get_drag_data()
		_set_hot(data is ItemDef)
	elif what == Node.NOTIFICATION_DRAG_END:
		_set_hot(false)


func _set_hot(v: bool) -> void:
	if _sb_normal == null or _sb_hot == null:
		return
	add_theme_stylebox_override("panel", _sb_hot if v else _sb_normal)


func _auto_craft() -> bool:
	var crafted_any := false
	var guard := 0

	while guard < 100:
		var crafted := false

		for r in DataManager.all_recipes:
			if r == null or r.result == null:
				continue

			if _try_apply_recipe_once(r):
				crafted = true
				crafted_any = true
				break

		if not crafted:
			break

		guard += 1

	return crafted_any


func _try_apply_recipe_once(r: RecipeDef) -> bool:
	var need: Dictionary = {}

	for c in r.components:
		if c == null:
			return false
		need[c.id] = int(need.get(c.id, 0)) + 1

	# один раз считаем, что уже лежит на столе
	var have := _build_counts(items)

	if r.requires_variant:
		var chosen_variant: StringName = StringName()

		for opt in r.variant_options:
			if opt == null:
				continue
			if int(have.get(opt.id, 0)) > 0:
				chosen_variant = opt.id
				break

		if chosen_variant == StringName():
			return false

		need[chosen_variant] = int(need.get(chosen_variant, 0)) + 1

	# проверяем хватает ли
	for k in need.keys():
		if int(have.get(k, 0)) < int(need[k]):
			return false

	_consume_by_need(need)
	items.append(r.result)
	return true


func _build_counts(arr: Array[ItemDef]) -> Dictionary:
	var out: Dictionary = {}
	for it in arr:
		if it == null:
			continue
		out[it.id] = int(out.get(it.id, 0)) + 1
	return out


func _consume_by_need(need: Dictionary) -> void:
	for k in need.keys():
		var times := int(need[k])
		for _i in range(times):
			_remove_one_by_id(k)


func _remove_one_by_id(id: StringName) -> void:
	for i in range(items.size()):
		if items[i].id == id:
			items.remove_at(i)
			return
