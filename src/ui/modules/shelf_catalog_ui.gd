extends Control
class_name ShelfCatalogUI

signal filters_changed
signal fav_changed(item_id: StringName, is_fav: bool)

@onready var search_edit: LineEdit = %SearchEdit
@onready var category_option: OptionButton = %CategoryOption
@onready var shelf_grid: GridContainer = %ShelfGrid
@onready var fav_only_button: Button = %FavOnlyButton

var _cat_index_to_id: Dictionary = {} # int -> StringName
var _signals_connected := false
var _shelf_items: Array[ShelfItem] = []

func _ready() -> void:
	_setup_categories_from_data()
	_connect_signals_once()

func _connect_signals_once() -> void:
	if _signals_connected:
		return
	_signals_connected = true

	search_edit.text_changed.connect(func(_t: String) -> void:
		filters_changed.emit()
	)
	category_option.item_selected.connect(func(_idx: int) -> void:
		filters_changed.emit()
	)
	fav_only_button.toggled.connect(func(_v: bool) -> void:
		filters_changed.emit()
	)

func _setup_categories_from_data() -> void:
	_cat_index_to_id.clear()
	category_option.clear()

	category_option.add_item("All")
	_cat_index_to_id[0] = &"__all__"

	var cats: Dictionary = {}
	for v in DataManager.items_by_id.values():
		var item := v as ItemDef
		if item == null:
			continue

		var t := String(item.type).to_lower()
		if t != "base" and t != "recipe_scroll":
			continue

		var c := String(item.category).to_lower()
		if c.is_empty():
			c = "misc"
		cats[StringName(c)] = true

	var cat_list: Array[StringName] = []
	for k in cats.keys():
		cat_list.append(k)
	cat_list.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)

	for cat_id in cat_list:
		var idx := category_option.get_item_count()
		category_option.add_item(String(cat_id))
		_cat_index_to_id[idx] = cat_id

	category_option.select(0)
	search_edit.text = ""
	fav_only_button.button_pressed = false

func get_query() -> String:
	return search_edit.text.strip_edges().to_lower()

func is_fav_only() -> bool:
	return fav_only_button.button_pressed

func get_selected_category() -> StringName:
	var sel_idx := category_option.get_selected()
	return _cat_index_to_id.get(sel_idx, &"__all__")

func rebuild(shop_level: int, fav_ids: Dictionary) -> void:
	# очистка грида
	for c in shelf_grid.get_children():
		c.queue_free()
	_shelf_items.clear()

	var lvl := maxi(1, shop_level)
	var query := get_query()
	var sel_cat := get_selected_category()
	var fav_only := is_fav_only()

	var candidates: Array[ItemDef] = []

	for v in DataManager.items_by_id.values():
		var item := v as ItemDef
		if item == null:
			continue

		var t := String(item.type).to_lower()
		if t != "base" and t != "recipe_scroll":
			continue

		if item.tier > lvl:
			continue

		var c_id := String(item.category).to_lower()
		if c_id.is_empty():
			c_id = "misc"
		if sel_cat != &"__all__" and c_id != String(sel_cat).to_lower():
			continue

		if fav_only and not fav_ids.has(item.id):
			continue

		if not query.is_empty():
			var nk := String(item.name_key)
			var name := tr(nk)
			if name == nk:
				name = String(item.id)
			name = name.to_lower()
			var id_s := String(item.id).to_lower()
			if name.find(query) == -1 and id_s.find(query) == -1:
				continue

		candidates.append(item)

	candidates.sort_custom(func(a: ItemDef, b: ItemDef) -> bool:
		var af := fav_ids.has(a.id)
		var bf := fav_ids.has(b.id)
		if af != bf:
			return af and not bf

		var a_has := DataManager.has_stock(a.id)
		var b_has := DataManager.has_stock(b.id)
		if a_has != b_has:
			return a_has and not b_has

		if a.cost != b.cost:
			return a.cost < b.cost

		return String(a.id) < String(b.id)
	)

	var shelf_item_scene := preload("res://scenes/ui/shelf_item.tscn")
	for item in candidates:
		var node := shelf_item_scene.instantiate() as ShelfItem
		node.item = item
		shelf_grid.add_child(node)
		_shelf_items.append(node)

		if node.has_method("set_fav"):
			node.call("set_fav", fav_ids.has(item.id))
		if node.has_signal("fav_toggled"):
			node.connect("fav_toggled", Callable(self, "_on_item_fav_toggled"))

	refresh_stock()

func refresh_stock() -> void:
	for s in _shelf_items:
		if s != null:
			if s.has_method("refresh"):
				s.refresh()
			else:
				s._apply_view()

func _on_item_fav_toggled(id: StringName, v: bool) -> void:
	fav_changed.emit(id, v)
