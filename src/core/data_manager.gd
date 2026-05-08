extends Node

@export var items_dir: String = "res://data/items"
@export var recipes_dir: String = "res://data/recipes"

const DEFAULT_STOCK_MAX := 20

var items_by_id: Dictionary = {}            # StringName -> ItemDef
var recipes_by_result_id: Dictionary = {}   # StringName -> RecipeDef
var all_recipes: Array[RecipeDef] = []

# склад
var stock: Dictionary = {}                  # StringName -> int (текущий)
var stock_max_by_id: Dictionary = {}        # StringName -> int (максимум, уже "разрешённый" с дефолтом)

var load_report: String = ""

func _ready() -> void:
	reload_database()

func reload_database() -> void:
	items_by_id.clear()
	recipes_by_result_id.clear()
	all_recipes.clear()
	stock.clear()
	stock_max_by_id.clear()

	var item_files := _load_items_from_dir(items_dir)
	var recipe_files := _load_recipes_from_dir(recipes_dir)
	
	for r in recipes_by_result_id.values():
		var rr := r as RecipeDef
		if rr != null:
			all_recipes.append(rr)
	
	all_recipes.sort_custom(func(a: RecipeDef, b: RecipeDef) -> bool:
		var ac := (a.result.cost if a != null and a.result != null else 0)
		var bc := (b.result.cost if b != null and b.result != null else 0)
		if ac != bc:
			return ac > bc
		var aid := (String(a.result.id) if a != null and a.result != null else "")
		var bid := (String(b.result.id) if b != null and b.result != null else "")
		return aid < bid
	)
	
	_build_stock_tables()
	
	load_report = "DB loaded. Item files: %d, Recipe files: %d, Items: %d, Recipes: %d, Stock items: %d" % [
		item_files, recipe_files, items_by_id.size(), all_recipes.size(), stock.size()
	]

func _build_stock_tables() -> void:
	# Склад ведём только для базовых предметов (type == "base")
	for it in items_by_id.values():
		var item := it as ItemDef
		if item == null:
			continue
	
		if item.type != &"base":
			continue
	
		var maxv := item.stock_max
		if maxv <= 0:
			maxv = DEFAULT_STOCK_MAX
	
		stock_max_by_id[item.id] = maxv
		stock[item.id] = maxv

func get_item(id: StringName) -> ItemDef:
	return items_by_id.get(id, null)

func get_recipe(result_id: StringName) -> RecipeDef:
	return recipes_by_result_id.get(result_id, null)

func _load_items_from_dir(dir_path: String) -> int:
	return _scan_dir_recursive(dir_path, func(path: String) -> void:
		var item := ResourceLoader.load(path) as ItemDef
		if item != null and item.id != StringName():
			items_by_id[item.id] = item
	)

func _load_recipes_from_dir(dir_path: String) -> int:
	return _scan_dir_recursive(dir_path, func(path: String) -> void:
		var recipe := ResourceLoader.load(path) as RecipeDef
		if recipe != null and recipe.result != null:
			recipes_by_result_id[recipe.result.id] = recipe
	)

func _scan_dir_recursive(dir_path: String, on_file: Callable) -> int:
	var count := 0
	var entries: PackedStringArray = ResourceLoader.list_directory(dir_path)
	entries.sort()

	for name in entries:
		if name.ends_with("/"):
			count += _scan_dir_recursive(dir_path + "/" + name.trim_suffix("/"), on_file)
			continue

		var ext := name.get_extension().to_lower()
		if ext != "tres" and ext != "res":
			continue

		on_file.call(dir_path + "/" + name)
		count += 1

	return count

# ---- API склада ----

func is_stocked(id: StringName) -> bool:
	return stock_max_by_id.has(id)

func get_stock(id: StringName) -> int:
	return int(stock.get(id, 0))

func get_stock_max(id: StringName) -> int:
	if not is_stocked(id):
		return 0
	return int(stock_max_by_id[id])

func get_stock_for_ui(id: StringName) -> int:
	if not is_stocked(id):
		return -1 # значит "∞"
	return get_stock(id)

func has_stock(id: StringName) -> bool:
	if not is_stocked(id):
		return true
	return int(stock.get(id, 0)) > 0

func spend_stock(id: StringName) -> bool:
	if not is_stocked(id):
		return true
	var s := int(stock.get(id, 0))
	if s <= 0:
		return false
	stock[id] = s - 1
	return true

func restock_all() -> void:
	for id in stock_max_by_id.keys():
		stock[id] = int(stock_max_by_id[id])

func replenish_tick(amount: int = 1) -> void:
	for id in stock_max_by_id.keys():
		var maxv := int(stock_max_by_id[id])
		var s := int(stock.get(id, 0))
		if s < maxv:
			stock[id] = min(maxv, s + amount)

func add_stock_capacity_bonus(amount: int) -> void:
	for id in stock_max_by_id.keys():
		stock_max_by_id[id] = int(stock_max_by_id[id]) + amount
		# текущий stock не увеличиваем, только не даём превысить новый max
		var s := int(stock.get(id, 0))
		stock[id] = min(int(stock_max_by_id[id]), s)

func add_stock(id: StringName, amount: int = 1) -> void:
	if not is_stocked(id):
		return
	var maxv := int(stock_max_by_id[id])
	var s := int(stock.get(id, 0))
	stock[id] = clampi(s + amount, 0, maxv)

func get_stock_state() -> Dictionary:
	var d: Dictionary = {}
	for id in stock.keys():
		d[String(id)] = int(stock[id])
	return d

func set_stock_state(d: Dictionary) -> void:
	for k in d.keys():
		var id := StringName(String(k))
		if not is_stocked(id):
			continue
		var maxv := int(stock_max_by_id[id])
		stock[id] = clampi(int(d[k]), 0, maxv)
