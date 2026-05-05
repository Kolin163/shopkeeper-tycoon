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

const QUEUE_SIZE := 3
const APPROACH_TIME := 0.7
const ANNOUNCE_TIME := 0.4
const QUEUE_DRAIN_MULT := 0.25

const FAST_TIME := 4.0
const MOOD_OK := 0.66
const MOOD_WARN := 0.33

const RESTOCK_COST_PER_TYPE := 50
const REPLENISH_PERIOD := 5.0

var craft_areas: Array[CraftArea] = []
var shelf_items: Array[ShelfItem] = []

var active_customer: Customer = null
var queue_customers: Array[Customer] = []
var gold := 0
var combo := 0
var replenish_timer: Timer

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

	_build_shelf()
	_collect_craft_areas()

	_fill_queue()
	_promote_next_customer()
	_update_ui()
	_update_shelf_badges()

	replenish_timer = Timer.new()
	replenish_timer.wait_time = REPLENISH_PERIOD
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
	c.order_id = order_pool[randi() % order_pool.size()]
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

			status_label.text = "Delivered!"
			active_customer = null
			_promote_next_customer()

			call_deferred("_try_deliver_current_order")
			return


# ---------- UI и склад ----------

func _update_ui() -> void:
	gold_label.text = "Gold: %d" % gold
	combo_label.text = "Combo: %d" % combo

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
	DataManager.replenish_tick()
	_update_shelf_badges()


func _update_shelf_badges() -> void:
	for shelf in shelf_items:
		if shelf != null:
			# лучше вызывать публичный refresh(), если добавишь его в ShelfItem
			shelf.refresh() if shelf.has_method("refresh") else shelf._apply_view()
