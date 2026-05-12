extends Node

@export var items_json_path: String = "res://data/items.json"
@export var recipes_json_path: String = "res://data/recipes.json"

const DEFAULT_STOCK_MAX := 20

var items_by_id: Dictionary = {}            # StringName -> ItemDef
var recipes_by_result_id: Dictionary = {}   # StringName -> RecipeDef
var all_recipes: Array[RecipeDef] = []

# склад
var stock: Dictionary = {}                  # StringName -> int
var stock_max_by_id: Dictionary = {}        # StringName -> int

var load_report: String = ""

func _ready() -> void:
	reload_database()

func reload_database() -> void:
	items_by_id.clear()
	recipes_by_result_id.clear()
	all_recipes.clear()
	stock.clear()
	stock_max_by_id.clear()

	var items_src := _load_json_dict(items_json_path)
	var recipes_src := _load_json_dict(recipes_json_path)

	if items_src.is_empty():
		load_report = "DB ERROR: items.json not loaded: %s" % items_json_path
		return
	if recipes_src.is_empty():
		load_report = "DB ERROR: recipes.json not loaded: %s" % recipes_json_path
		return

	# 1) items -> ItemDef (in-memory)
	for key in items_src.keys():
		var id_s := String(key)
		var row = items_src[key]
		if not (row is Dictionary):
			continue

		var it := ItemDef.new()
		it.id = StringName(id_s)
		it.name_key = StringName(String(row.get("name_key", "item." + id_s)))
		it.category = StringName(String(row.get("category", "misc")))
		it.type = StringName(String(row.get("type", "base")))
		it.tier = int(row.get("tier", 1))
		it.cost = int(row.get("cost", 0))
		it.stock_max = int(row.get("stock_max", 0))

		var icon_path := String(row.get("icon", ""))
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			var tex := ResourceLoader.load(icon_path) as Texture2D
			it.icon = tex

		items_by_id[it.id] = it

	# 2) recipes -> RecipeDef (in-memory, with references)
	for key in recipes_src.keys():
		var result_s := String(key)
		var row = recipes_src[key]
		if not (row is Dictionary):
			continue

		var result_id := StringName(result_s)
		var result_item := get_item(result_id)
		if result_item == null:
			# рецепт на неизвестный предмет — пропускаем (потом валидатором отловишь)
			continue

		var r := RecipeDef.new()
		r.result = result_item
		r.requires_variant = bool(row.get("requires_variant", false))

		# components
		var comps = row.get("components", [])
		if comps is Array:
			for c in comps:
				var cid := StringName(String(c))
				var comp_item := get_item(cid)
				if comp_item != null:
					r.components.append(comp_item)

		# variant options
		var vars = row.get("variant_options", [])
		if vars is Array:
			for v in vars:
				var vid := StringName(String(v))
				var opt_item := get_item(vid)
				if opt_item != null:
					r.variant_options.append(opt_item)

		recipes_by_result_id[result_id] = r
		all_recipes.append(r)

	# 3) deterministic order for autocraft
	all_recipes.sort_custom(func(a: RecipeDef, b: RecipeDef) -> bool:
		var ac := a.result.cost
		var bc := b.result.cost
		if ac != bc:
			return ac > bc
		return String(a.result.id) < String(b.result.id)
	)

	# 4) stock tables (base only)
	_build_stock_tables()

	load_report = "DB loaded from JSON.\nItems: %d\nRecipes: %d\nStock items: %d" % [
		items_by_id.size(), all_recipes.size(), stock.size()
	]

func _build_stock_tables() -> void:
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

func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var v = JSON.parse_string(text)
	return v if typeof(v) == TYPE_DICTIONARY else {}

# ----- API (как у тебя было) -----

func get_item(id: StringName) -> ItemDef:
	return items_by_id.get(id, null)

func get_recipe(result_id: StringName) -> RecipeDef:
	return recipes_by_result_id.get(result_id, null)

func is_stocked(id: StringName) -> bool:
	return stock_max_by_id.has(id)

func get_stock(id: StringName) -> int:
	return int(stock.get(id, 0))

func get_stock_for_ui(id: StringName) -> int:
	if not is_stocked(id):
		return -1
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

func add_stock(id: StringName, amount: int = 1) -> void:
	if not is_stocked(id):
		return
	var maxv := int(stock_max_by_id[id])
	var s := int(stock.get(id, 0))
	stock[id] = clampi(s + amount, 0, maxv)

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
		var s := int(stock.get(id, 0))
		stock[id] = min(int(stock_max_by_id[id]), s)

# --- state for saves ---
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
