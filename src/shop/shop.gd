extends Control

enum CustomerState { QUEUE, APPROACHING, ANNOUNCING, SERVING }

class Customer:
	var order_id: StringName
	var state: int = CustomerState.QUEUE
	var state_time: float = 0.0

	var queue_patience_max: float = 10.0
	var queue_patience: float = 10.0

	var serve_patience_max: float = 12.0
	var serve_patience: float = 12.0
	var serve_time: float = 0.0


@onready var db_label: Label = $VBoxContainer/DbLabel
@onready var gold_label: Label = $VBoxContainer/TopBar/GoldLabel
@onready var combo_label: Label = $VBoxContainer/TopBar/ComboLabel
@onready var restock_button: Button = $VBoxContainer/TopBar/RestockButton
@onready var queue_label: Label = $VBoxContainer/OrderBar/QueueLabel
@onready var order_label: Label = $VBoxContainer/OrderBar/OrderLabel
@onready var need_label: Label = $VBoxContainer/OrderBar/NeedLabel
@onready var status_label: Label = $VBoxContainer/OrderBar/StatusLabel
@onready var clear_button: Button = $VBoxContainer/OrderBar/ClearButton
@onready var patience_bar: ProgressBar = $VBoxContainer/OrderBar/PatienceBar
@onready var mood_label: Label = $VBoxContainer/OrderBar/MoodLabel
@onready var craft_row: HBoxContainer = $VBoxContainer/CraftRow
@onready var shelf_flow: Control = $VBoxContainer/ShelfFlow
@onready var upgrades_button: Button = $VBoxContainer/TopBar/UpgradesButton
@onready var upgrades_panel: PanelContainer = $VBoxContainer/UpgradesPanel
@onready var btn_more_tables: Button = $VBoxContainer/UpgradesContainer/VBoxContainer/BtnMoreTables
@onready var btn_more_stock: Button = $VBoxContainer/UpgradesContainer/VBoxContainer/BtnMoreStock
@onready var btn_replenish: Button = $VBoxContainer/UpgradesContainer/VBoxContainer/BtnReplenish
@onready var btn_more_patience: Button = $VBoxContainer/UpgradesContainer/VBoxContainer/BtnMorePatience
@onready var btn_close_upgrades: Button = $VBoxContainer/UpgradesContainer/VBoxContainer/BtnCloseUpgrades
@onready var level_label: Label = $VBoxContainer/TopBar/LevelLabel

const QUEUE_SIZE := 3
const APPROACH_TIME := 0.7
const ANNOUNCE_TIME := 0.4
const QUEUE_DRAIN_MULT := 0.25

const FAST_TIME := 4.0
const MOOD_OK := 0.66
const MOOD_WARN := 0.33
const DELIVERIES_PER_LEVEL := 5 
const RESTOCK_COST_PER_TYPE := 50
const REPLENISH_PERIOD := 5.0

var _craftable_cache: Dictionary = {} # StringName -> bool (memo)
var craft_areas: Array[CraftArea] = []
var shelf_items: Array[ShelfItem] = []
var unlocked_orders: Array[StringName] = []
var active_customer: Customer = null
var queue_customers: Array[Customer] = []
var gold := 0
var combo := 0
var deliveries := 0
var replenish_timer: Timer
var shop_level := 1
var upg_tables := 0       # +1 стол за уровень
var upg_stock := 0        # +capacity
var upg_replenish := 0    # быстрее пополнение
var upg_patience := 0     # больше терпение

var order_pool: Array[StringName] = [
	&"magic_wand",
	&"power_treads",
	&"tranquil_boots",
]

var shelf_ids: Array[StringName] = [
	&"boots",
	&"gloves",
	&"belt_of_strength",
	&"robe_of_magi",
	&"band_of_elvenskin",
	&"magic_stick",
	&"iron_branch",
	&"wind_lace",
	&"ring_of_regen",
]


func _ready() -> void:
	db_label.text = "%s\nAll recipes: %d" % [DataManager.load_report, DataManager.all_recipes.size()]
	
	clear_button.text = "Clear"
	clear_button.pressed.connect(_on_clear_pressed)
	restock_button.pressed.connect(_on_restock_pressed)
	
	upgrades_button.pressed.connect(func():
		upgrades_panel.visible = true
		_refresh_upgrades_ui()
	)
	
	btn_close_upgrades.pressed.connect(func():
		upgrades_panel.visible = false
	)
	
	btn_more_tables.pressed.connect(_buy_more_tables)
	btn_more_stock.pressed.connect(_buy_more_stock)
	btn_replenish.pressed.connect(_buy_replenish)
	btn_more_patience.pressed.connect(_buy_more_patience)
	
	_build_shelf()
	_rebuild_unlocked_orders()
	_collect_craft_areas()
	_apply_tables()
	_refresh_upgrades_ui()
	_fill_queue()
	_promote_next_customer()
	_update_ui()
	_update_shelf_badges()

	replenish_timer = Timer.new()
	replenish_timer.wait_time = _replenish_period()
	replenish_timer.timeout.connect(_on_replenish)
	add_child(replenish_timer)
	replenish_timer.start()


func _process(delta: float) -> void:
	_update_queue(delta)
	_update_active_customer(delta)
	_update_ui()


func _build_shelf() -> void:
	for c in shelf_flow.get_children():
		c.queue_free()

	shelf_items.clear()

	var shelf_item_scene := preload("res://scenes/ui/shelf_item.tscn")
	for id in shelf_ids:
		if not _is_unlocked_item(id):
			continue
		var def := DataManager.get_item(id)
		if def == null:
			continue
		var node := shelf_item_scene.instantiate() as ShelfItem
		node.item = def
		shelf_flow.add_child(node)
		shelf_items.append(node)


func _collect_craft_areas() -> void:
	craft_areas.clear()
	for child in craft_row.get_children():
		var area := child as CraftArea
		if area != null:
			craft_areas.append(area)
	
	for area in craft_areas:
		area.changed.connect(_on_craft_changed)


func _on_clear_pressed() -> void:
	for area in craft_areas:
		area.clear()


# ---------- Очередь и клиенты ----------

func _spawn_customer() -> Customer:
	var c := Customer.new()
	if unlocked_orders.is_empty():
		_rebuild_unlocked_orders()
	c.order_id = unlocked_orders[randi() % unlocked_orders.size()]
	c.queue_patience = c.queue_patience_max
	return c


func _fill_queue() -> void:
	while queue_customers.size() < QUEUE_SIZE:
		queue_customers.append(_spawn_customer())


func _promote_next_customer() -> void:
	if active_customer != null:
		return
	if queue_customers.is_empty():
		_fill_queue()

	active_customer = queue_customers.pop_front()
	active_customer.state = CustomerState.APPROACHING
	active_customer.state_time = APPROACH_TIME

	status_label.text = "Customer approaching..."
	_update_need_label()


func _update_queue(delta: float) -> void:
	for i in range(queue_customers.size() - 1, -1, -1):
		var c := queue_customers[i]
		c.queue_patience -= delta * QUEUE_DRAIN_MULT
		if c.queue_patience <= 0.0:
			queue_customers.remove_at(i)
			combo = 0
			status_label.text = "Someone left the queue!"
	_fill_queue()


func _update_active_customer(delta: float) -> void:
	if active_customer == null:
		_promote_next_customer()
		return

	match active_customer.state:
		CustomerState.APPROACHING:
			active_customer.state_time -= delta
			if active_customer.state_time <= 0.0:
				active_customer.state = CustomerState.ANNOUNCING
				active_customer.state_time = ANNOUNCE_TIME
				status_label.text = "..."
		CustomerState.ANNOUNCING:
			active_customer.state_time -= delta
			if active_customer.state_time <= 0.0:
				active_customer.state = CustomerState.SERVING
				active_customer.serve_patience_max = _serve_patience_max()
				active_customer.serve_patience = active_customer.serve_patience_max
				active_customer.serve_time = 0.0
				status_label.text = "Order shown!"
				_update_need_label()
				_try_deliver_current_order()
		CustomerState.SERVING:
			active_customer.serve_patience -= delta
			active_customer.serve_time += delta
			if active_customer.serve_patience <= 0.0:
				_on_active_left()


func _on_active_left() -> void:
	status_label.text = "Customer left!"
	combo = 0
	active_customer = null
	_promote_next_customer()


# ---------- Крафт и выдача ----------

func _update_need_label() -> void:
	if active_customer == null or active_customer.state != CustomerState.SERVING:
		need_label.text = "Need: (hidden)"
		return

	var r := DataManager.get_recipe(active_customer.order_id)
	if r == null:
		need_label.text = "Need: ?"
		return

	var parts: Array[String] = []
	for c in r.components:
		if c != null:
			parts.append(_safe_name(c))

	if r.requires_variant and not r.variant_options.is_empty():
		var opts: Array[String] = []
		for o in r.variant_options:
			if o != null:
				opts.append(_safe_name(o))
		parts.append("(" + " / ".join(opts) + ")")

	need_label.text = "Need: " + " + ".join(parts)


func _on_craft_changed() -> void:
	_try_deliver_current_order()
	_update_shelf_badges()


func _try_deliver_current_order() -> void:
	if active_customer == null or active_customer.state != CustomerState.SERVING:
		return

	var order_id := active_customer.order_id

	for area in craft_areas:
		if area.has_item(order_id):
			area.remove_one(order_id, false)

			var result := DataManager.get_item(order_id)
			var base_gold := result.cost if result else 0

			if active_customer.serve_time <= FAST_TIME:
				combo += 1
			else:
				combo = 0

			var bonus_mult := 1.0 + float(combo) * 0.05
			gold += int(round(float(base_gold) * bonus_mult))
			deliveries += 1
			if deliveries % DELIVERIES_PER_LEVEL == 0:
				shop_level += 1
				status_label.text = "Level up! Level: %d" % shop_level

				_build_shelf()
				_update_shelf_badges()
				_rebuild_unlocked_orders()
				_refresh_upgrades_ui()
			status_label.text = "Delivered!"
			active_customer = null
			_promote_next_customer()

			call_deferred("_try_deliver_current_order")
			return


# ---------- UI и склад ----------

func _update_ui() -> void:
	gold_label.text = "Gold: %d" % gold
	combo_label.text = "Combo: %d" % combo
	level_label.text = "Level: %d" % shop_level
	
	if active_customer == null:
		order_label.text = "Order: -"
		patience_bar.value = 0
		mood_label.text = "-"
	else:
		if active_customer.state != CustomerState.SERVING:
			order_label.text = "Order: (hidden)"
			patience_bar.value = 100
			mood_label.text = "..."
		else:
			var it := DataManager.get_item(active_customer.order_id)
			order_label.text = "Order: " + (_safe_name(it) if it else String(active_customer.order_id))

			var t = clamp(active_customer.serve_patience / active_customer.serve_patience_max, 0.0, 1.0)
			patience_bar.value = t * 100.0
			mood_label.text = "OK" if t > MOOD_OK else ("WARN" if t > MOOD_WARN else "ANGRY")

	var q: Array[String] = []
	for c in queue_customers:
		var t2 = clamp(c.queue_patience / c.queue_patience_max, 0.0, 1.0)
		q.append(str(int(round(t2 * 100.0))) + "%")
	queue_label.text = "Queue: " + ", ".join(q)


func _safe_name(it: ItemDef) -> String:
	if it == null:
		return "?"
	var key := String(it.name_key)
	var s := tr(key)
	return s if s != key else String(it.id)


func _on_restock_pressed() -> void:
	var types := DataManager.stock_max_by_id.size()
	var cost := RESTOCK_COST_PER_TYPE * types

	if gold < cost:
		status_label.text = "Not enough gold!"
		return

	gold -= cost
	DataManager.restock_all()
	status_label.text = "Restocked!"
	_update_shelf_badges()


func _on_replenish() -> void:
	DataManager.replenish_tick(_replenish_amount())
	_update_shelf_badges()


func _update_shelf_badges() -> void:
	for shelf in shelf_items:
		if shelf != null:
			# лучше вызывать публичный refresh(), если добавишь его в ShelfItem
			shelf.refresh() if shelf.has_method("refresh") else shelf._apply_view()

func _active_table_count() -> int:
	return clamp(1 + upg_tables, 1, craft_areas.size())

func _apply_tables() -> void:
	var n := _active_table_count()
	for i in range(craft_areas.size()):
		craft_areas[i].set_enabled(i < n)

func _replenish_period() -> float:
	return max(1.5, 5.0 - float(upg_replenish) * 0.5)

func _replenish_amount() -> int:
	return 1 + upg_replenish

func _serve_patience_max() -> float:
	return 12.0 + float(upg_patience) * 2.0

func _cost_more_tables() -> int: return 300 + upg_tables * 400
func _cost_more_stock() -> int: return 200 + upg_stock * 250
func _cost_replenish() -> int: return 250 + upg_replenish * 300
func _cost_more_patience() -> int: return 200 + upg_patience * 250

func _buy_more_tables() -> void:
	if _active_table_count() >= craft_areas.size():
		status_label.text = "Max tables"
		return
	var cost := _cost_more_tables()
	if gold < cost:
		status_label.text = "Not enough gold!"
		return
	gold -= cost
	upg_tables += 1
	_apply_tables()
	_refresh_upgrades_ui()

func _buy_more_stock() -> void:
	var cost := _cost_more_stock()
	if gold < cost:
		status_label.text = "Not enough gold!"
		return
	gold -= cost
	upg_stock += 1
	DataManager.add_stock_capacity_bonus(10) # +10 к max для всех base
	_refresh_upgrades_ui()

func _buy_replenish() -> void:
	var cost := _cost_replenish()
	if gold < cost:
		status_label.text = "Not enough gold!"
		return
	gold -= cost
	upg_replenish += 1
	replenish_timer.wait_time = _replenish_period()
	_refresh_upgrades_ui()

func _buy_more_patience() -> void:
	var cost := _cost_more_patience()
	if gold < cost:
		status_label.text = "Not enough gold!"
		return
	gold -= cost
	upg_patience += 1
	_refresh_upgrades_ui()

func _refresh_upgrades_ui() -> void:
	btn_more_tables.text = "More tables (%d/%d) - %dg" % [_active_table_count(), craft_areas.size(), _cost_more_tables()]
	btn_more_stock.text = "Bigger stock (lvl %d) - %dg" % [upg_stock, _cost_more_stock()]
	btn_replenish.text = "Faster replenish (lvl %d) - %dg" % [upg_replenish, _cost_replenish()]
	btn_more_patience.text = "More patience (lvl %d) - %dg" % [upg_patience, _cost_more_patience()]

func _is_unlocked_item(id: StringName) -> bool:
	var it := DataManager.get_item(id)
	return it != null and it.tier <= shop_level

# ВАЖНО: сейчас мы считаем, что base должен быть доступен игроку на полке,
# иначе он физически не сможет его перетащить.
# (Когда появится “каталог/поиск” по предметам, эту проверку можно убрать/заменить.)
func _is_base_available(id: StringName) -> bool:
	return shelf_ids.has(id) and _is_unlocked_item(id)

func _can_craft_at_level(id: StringName, stack: Array[StringName] = []) -> bool:
	# memo
	if _craftable_cache.has(id):
		return bool(_craftable_cache[id])

	# защита от циклов (на всякий случай)
	if stack.has(id):
		_craftable_cache[id] = false
		return false

	var it := DataManager.get_item(id)
	if it == null:
		_craftable_cache[id] = false
		return false

	# если сам предмет ещё не открыт — точно нельзя
	if it.tier > shop_level:
		_craftable_cache[id] = false
		return false

	# базовый / recipe_scroll: “можно получить”, если он вообще доступен игроку
	if it.type == &"base" or it.type == &"recipe_scroll":
		var ok := _is_base_available(id)
		_craftable_cache[id] = ok
		return ok

	# upgrade: нужен рецепт
	var r := DataManager.get_recipe(id)
	if r == null:
		_craftable_cache[id] = false
		return false

	stack.append(id)

	# все обязательные компоненты должны быть крафтабельны
	for c in r.components:
		if c == null or not _can_craft_at_level(c.id, stack):
			stack.pop_back()
			_craftable_cache[id] = false
			return false

	# вариант “1 из N” (power treads): достаточно хотя бы одного крафтабельного
	if r.requires_variant:
		var any_ok := false
		for opt in r.variant_options:
			if opt != null and _can_craft_at_level(opt.id, stack):
				any_ok = true
				break
		if not any_ok:
			stack.pop_back()
			_craftable_cache[id] = false
			return false

	stack.pop_back()
	_craftable_cache[id] = true
	return true

func _rebuild_unlocked_orders() -> void:
	unlocked_orders.clear()
	_craftable_cache.clear()

	for id in order_pool:
		# 1) сам результат открыт
		# 2) и реально собирается из доступных базовых
		if _is_unlocked_item(id) and _can_craft_at_level(id):
			unlocked_orders.append(id)

	# чтобы не остаться без заказов (на очень раннем этапе)
	if unlocked_orders.is_empty():
		for id in order_pool:
			if _is_unlocked_item(id):
				unlocked_orders.append(id)
