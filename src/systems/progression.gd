class_name Progression
extends RefCounted

signal level_changed(new_level: int)

var shop_level: int = 1
var deliveries: int = 0
var deliveries_per_level: int = 5

var order_pool: Array[StringName] = []
var shelf_ids: Array[StringName] = []

var unlocked_orders: Array[StringName] = []
var _craftable_cache: Dictionary = {} # StringName -> bool

func setup(p_order_pool: Array[StringName], p_shelf_ids: Array[StringName]) -> void:
	order_pool = p_order_pool.duplicate()
	shelf_ids = p_shelf_ids.duplicate()
	rebuild_unlocked_orders()

func on_delivered() -> bool:
	deliveries += 1
	if deliveries % deliveries_per_level == 0:
		shop_level += 1
		_craftable_cache.clear()
		rebuild_unlocked_orders()
		level_changed.emit(shop_level)
		return true
	return false

func pick_order_id() -> StringName:
	if unlocked_orders.is_empty():
		rebuild_unlocked_orders()
	if unlocked_orders.is_empty():
		return StringName()
	return unlocked_orders[randi() % unlocked_orders.size()]

func rebuild_unlocked_orders() -> void:
	unlocked_orders.clear()
	_craftable_cache.clear()

	for id in order_pool:
		if _is_unlocked_item(id) and _can_craft_at_level(id):
			unlocked_orders.append(id)

	# fallback: хотя бы что-то
	if unlocked_orders.is_empty():
		for id in order_pool:
			if _is_unlocked_item(id):
				unlocked_orders.append(id)

func _is_unlocked_item(id: StringName) -> bool:
	var it = DataManager.get_item(id)
	return it != null and it.tier <= shop_level

func _is_base_available(id: StringName) -> bool:
	var it = DataManager.get_item(id)
	return it != null and (it.type == &"base" or it.type == &"recipe_scroll") and it.tier <= shop_level

func _can_craft_at_level(id: StringName) -> bool:
	return _can_craft_at_level_impl(id, [])

func _can_craft_at_level_impl(id: StringName, stack: Array[StringName]) -> bool:
	if _craftable_cache.has(id):
		return bool(_craftable_cache[id])

	if stack.has(id):
		_craftable_cache[id] = false
		return false

	var it = DataManager.get_item(id)
	if it == null or it.tier > shop_level:
		_craftable_cache[id] = false
		return false

	if it.type == &"base" or it.type == &"recipe_scroll":
		var ok := _is_base_available(id)
		_craftable_cache[id] = ok
		return ok

	var r = DataManager.get_recipe(id)
	if r == null:
		_craftable_cache[id] = false
		return false

	stack.append(id)

	for c in r.components:
		if c == null or not _can_craft_at_level_impl(c.id, stack):
			stack.pop_back()
			_craftable_cache[id] = false
			return false

	if r.requires_variant:
		var any_ok := false
		for opt in r.variant_options:
			if opt != null and _can_craft_at_level_impl(opt.id, stack):
				any_ok = true
				break
		if not any_ok:
			stack.pop_back()
			_craftable_cache[id] = false
			return false

	stack.pop_back()
	_craftable_cache[id] = true
	return true
