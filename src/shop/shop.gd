extends Control

# Requires:
# - res://src/systems/upgrades.gd        (class_name Upgrades)
# - res://src/systems/progression.gd     (class_name Progression)
# - res://src/systems/customer_queue.gd  (class_name CustomerQueue)  [VIP multi-order version]
# - res://src/systems/hero_archetypes.gd (class_name HeroArchetypes)
# - res://src/systems/day_modifiers.gd   (class_name DayModifier, DayModifiers)

enum GamePhase { DAY_BREAK, DAY_ACTIVE, DAY_END }

# -----------------------------
# UI refs
# -----------------------------
@onready var db_label: Label = $VBoxContainer/DbLabel

@onready var gold_label: Label = $VBoxContainer/TopBar/GoldLabel
@onready var combo_label: Label = $VBoxContainer/TopBar/ComboLabel
@onready var level_label: Label = $VBoxContainer/TopBar/LevelLabel
@onready var day_label: Label = $VBoxContainer/TopBar/DayLabel
@onready var day_timer_label: Label = $VBoxContainer/TopBar/DayTimerLabel
@onready var day_mod_label: Label = $VBoxContainer/TopBar/DayModLabel
@onready var preps_label: Label = $VBoxContainer/TopBar/PrepsLabel
@onready var restock_button: Button = $VBoxContainer/TopBar/RestockButton
@onready var upgrades_button: Button = $VBoxContainer/TopBar/UpgradesButton

@onready var queue_label: Label = $VBoxContainer/OrderBar/QueueLabel
@onready var order_label: Label = $VBoxContainer/OrderBar/OrderLabel
@onready var need_label: Label = $VBoxContainer/OrderBar/NeedLabel
@onready var status_label: Label = $VBoxContainer/OrderBar/StatusLabel
@onready var clear_button: Button = $VBoxContainer/OrderBar/ClearButton
@onready var patience_bar: ProgressBar = $VBoxContainer/OrderBar/PatienceBar
@onready var mood_label: Label = $VBoxContainer/OrderBar/MoodLabel
@onready var hint_label: Label = $VBoxContainer/OrderBar/HintLabel
@onready var bargain_row: HBoxContainer = $VBoxContainer/OrderBar/BargainRow
@onready var bargain_label: Label = $VBoxContainer/OrderBar/BargainRow/BargainLabel
@onready var btn_deal: Button = $VBoxContainer/OrderBar/BargainRow/BtnDeal
@onready var btn_no_deal: Button = $VBoxContainer/OrderBar/BargainRow/BtnNoDeal

@onready var craft_row: HBoxContainer = $VBoxContainer/CraftRow
@onready var shelf_flow: Control = $VBoxContainer/ShelfFlow

@onready var day_break_panel: PanelContainer = $VBoxContainer/DayBreakPanel
@onready var start_day_button: Button = $VBoxContainer/DayBreakPanel/VBoxContainer/StartDayButton

@onready var end_day_panel: PanelContainer = $VBoxContainer/EndDayPanel
@onready var end_summary_label: Label = $VBoxContainer/EndDayPanel/VBoxContainer/EndSummaryLabel
@onready var to_break_button: Button = $VBoxContainer/EndDayPanel/VBoxContainer/ToBreakButton

@onready var upgrades_panel: PanelContainer = $VBoxContainer/UpgradesPanel
@onready var btn_more_tables: Button = $VBoxContainer/UpgradesPanel/VBoxContainer/BtnMoreTables
@onready var btn_more_stock: Button = $VBoxContainer/UpgradesPanel/VBoxContainer/BtnMoreStock
@onready var btn_replenish: Button = $VBoxContainer/UpgradesPanel/VBoxContainer/BtnReplenish
@onready var btn_more_patience: Button = $VBoxContainer/UpgradesPanel/VBoxContainer/BtnMorePatience
@onready var btn_close_upgrades: Button = $VBoxContainer/UpgradesPanel/VBoxContainer/BtnCloseUpgrades

# -----------------------------
# Tuning
# -----------------------------
const DAY_LENGTH := 180.0

const QUEUE_SIZE := 3
const APPROACH_TIME := 0.7
const ANNOUNCE_TIME := 0.4
const QUEUE_DRAIN_MULT := 0.25
const PREPS_PER_TABLE_LIMIT := 8
const FAST_TIME := 4.0
const MOOD_OK := 0.66
const MOOD_WARN := 0.33

const RESTOCK_COST_PER_TYPE := 50

const VIP_SET_BONUS_MULT := 0.20

# -----------------------------
# State / Models
# -----------------------------
var phase: int = GamePhase.DAY_BREAK
var day_index := 0
var day_time_left := 0.0

# day stats
var day_served := 0
var day_left := 0
var day_best_combo := 0
var day_gold_start := 0

var craft_areas: Array[CraftArea] = []
var shelf_items: Array[ShelfItem] = []

var gold := 0
var combo := 0

var upgrades := Upgrades.new()
var progression := Progression.new()
var customer_queue := CustomerQueue.new()

var day_mod: DayModifier = null

# VIP tracking (to pay set bonus on completion)
var vip_set_value := 0
var preps: Array[ItemDef] = []
# bargain state
var bargain_active := false
var bargain_discount_mult := 1.0
var bargain_patience_bonus := 0.0

# -----------------------------
# Content (MVP)
# -----------------------------
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

# -----------------------------
# Godot callbacks
# -----------------------------
func _ready() -> void:
	randomize()

	db_label.text = "%s\nAll recipes: %d" % [DataManager.load_report, DataManager.all_recipes.size()]

	# buttons
	clear_button.text = "Clear"
	clear_button.pressed.connect(_on_clear_pressed)

	start_day_button.pressed.connect(_start_day)
	to_break_button.pressed.connect(_go_to_break)

	restock_button.pressed.connect(_on_restock_pressed)

	upgrades_button.pressed.connect(func() -> void:
		if phase != GamePhase.DAY_BREAK:
			status_label.text = "Upgrades only in break"
			return
		upgrades_panel.visible = true
		_refresh_upgrades_ui()
	)
	btn_close_upgrades.pressed.connect(func() -> void:
		upgrades_panel.visible = false
	)

	btn_more_tables.pressed.connect(_buy_more_tables)
	btn_more_stock.pressed.connect(_buy_more_stock)
	btn_replenish.pressed.connect(_buy_replenish)
	btn_more_patience.pressed.connect(_buy_more_patience)

	bargain_row.visible = false
	btn_deal.pressed.connect(_accept_bargain)
	btn_no_deal.pressed.connect(_reject_bargain)

	# init world
	_build_shelf()
	_collect_craft_areas()
	_apply_tables()

	# progression
	progression.setup(order_pool, shelf_ids)
	progression.level_changed.connect(func(_lvl: int) -> void:
		_build_shelf()
		_update_shelf_badges()
		_refresh_upgrades_ui()
	)
	_load_game()
	_go_to_break(false)
	_update_ui()


func _process(delta: float) -> void:
	if phase == GamePhase.DAY_ACTIVE:
		day_time_left -= delta
		customer_queue.update(delta)
		if day_time_left <= 0.0:
			_end_day()

	_update_ui()

# -----------------------------
# Day flow
# -----------------------------
func _start_day() -> void:
	phase = GamePhase.DAY_ACTIVE
	day_index += 1
	day_time_left = DAY_LENGTH

	# pick day modifier
	day_mod = DayModifiers.pick()
	day_mod_label.text = "%s: %s" % [day_mod.title, day_mod.desc]

	# reset day stats
	day_served = 0
	day_left = 0
	day_best_combo = 0
	day_gold_start = gold
	combo = 0

	# reset per-day systems
	_reset_bargain()

	day_break_panel.visible = false
	end_day_panel.visible = false
	upgrades_panel.visible = false

	_apply_tables()

	# 1) всё, что игрок накрафтил в перерыве — собрать по твоему правилу:
	#    база -> склад, не база -> preps
	_collect_tables_to_stock_and_preps()
	_update_shelf_badges()

	# 2) очистить столы перед стартом дня (после сборки)
	for a in craft_areas:
		a.clear_silent()

	# 3) разложить заготовки на столы к началу дня
	_place_preps_on_tables()
	_update_shelf_badges()
	_update_recipe_hint()
	
	# VIP each 3rd day
	var vip_order_count := 0
	if day_index % 3 == 0:
		vip_order_count = 2 + (randi() % 2) # 2 or 3

	# restart customer queue for the day
	customer_queue.setup(
		Callable(self, "_make_order_ids"),
		Callable(self, "_pick_archetype"),
		Callable(self, "_serve_patience_max_for_day"),
		vip_order_count,
		QUEUE_SIZE, APPROACH_TIME, ANNOUNCE_TIME,
		QUEUE_DRAIN_MULT * _day_queue_drain_mult()
	)

	# connect (safe: disconnecting not necessary if setup() doesn't reconnect signals)
	_connect_customer_signals_once()

	status_label.text = "Day started!"

func _end_day() -> void:
	if phase != GamePhase.DAY_ACTIVE:
		return

	phase = GamePhase.DAY_END

	# 1) сначала забрать предметы со столов
	_collect_tables_to_stock_and_preps()
	_update_shelf_badges()
	_save_game()

	# 2) потом закрыть столы
	for a in craft_areas:
		a.set_enabled(false)

	end_day_panel.visible = true
	day_break_panel.visible = false
	upgrades_panel.visible = false
	bargain_row.visible = false

	var profit := gold - day_gold_start
	end_summary_label.text = "Day %d results:\nServed: %d\nLeft: %d\nBest combo: %d\nProfit: %d" % [
		day_index, day_served, day_left, day_best_combo, profit
	]

	status_label.text = "Day ended!"

func _place_preps_on_tables() -> void:
	if preps.is_empty():
		return

	var idx := 0
	for a in craft_areas:
		if not a.enabled:
			continue

		# ограничим, чтобы не превращать стол в мусорку
		while idx < preps.size() and a.get_items().size() < PREPS_PER_TABLE_LIMIT:
			a.put_items([preps[idx]], true)
			idx += 1

	if idx > 0:
		preps = preps.slice(idx)

func _collect_tables_to_stock_and_preps() -> void:
	for a in craft_areas:
		var taken := a.take_all_items(true)
		for it in taken:
			if it == null:
				continue
			if DataManager.is_stocked(it.id):
				# база -> на склад
				DataManager.add_stock(it.id, 1)
			else:
				# не база -> в заготовки
				preps.append(it)

func _go_to_break(apply_night_supply: bool = true) -> void:
	phase = GamePhase.DAY_BREAK

	day_break_panel.visible = true
	end_day_panel.visible = false
	upgrades_panel.visible = false
	bargain_row.visible = false

	_enable_workshop_tables()

	# Night supply: only after at least one played day
	if apply_night_supply and day_index > 0:
		_apply_night_supply()
	status_label.text = "Break"
	_refresh_upgrades_ui()
	_update_shelf_badges()
	_save_game()

# -----------------------------
# Night supply (Approach 2)
# -----------------------------
func _night_supply_amount() -> int:
	var base := 2 + upgrades.replenish_level
	var mult := day_mod.night_supply_mult if day_mod != null else 1.0
	return max(0, int(round(float(base) * mult)))

func _apply_night_supply() -> void:
	var amount := _night_supply_amount()
	DataManager.replenish_tick(amount)
	status_label.text = "Night supply: +%d each" % amount

# -----------------------------
# Day modifiers helpers
# -----------------------------
func _day_patience_mult() -> float:
	return day_mod.patience_mult if day_mod != null else 1.0

func _day_pay_mult() -> float:
	return day_mod.pay_mult if day_mod != null else 1.0

func _day_queue_drain_mult() -> float:
	return day_mod.queue_drain_mult if day_mod != null else 1.0

func _serve_patience_max_for_day() -> float:
	return upgrades.serve_patience_max() * _day_patience_mult()

# -----------------------------
# CustomerQueue signals
# -----------------------------
var _customer_signals_connected := false

func _connect_customer_signals_once() -> void:
	if _customer_signals_connected:
		return
	_customer_signals_connected = true

	customer_queue.active_promoted.connect(func() -> void:
		if phase == GamePhase.DAY_ACTIVE:
			status_label.text = "Customer approaching..."
			_reset_bargain()
			_update_need_label()
	)

	customer_queue.queue_customer_left.connect(func() -> void:
		if phase == GamePhase.DAY_ACTIVE:
			status_label.text = "Someone left the queue!"
			combo = 0
			day_left += 1
	)

	customer_queue.active_customer_left.connect(func() -> void:
		if phase == GamePhase.DAY_ACTIVE:
			status_label.text = "Customer left!"
			combo = 0
			day_left += 1
			_reset_bargain()
			_update_need_label()
	)

	customer_queue.order_shown.connect(func(_id: StringName) -> void:
		if phase != GamePhase.DAY_ACTIVE:
			return
		var a := customer_queue.get_active()
		if a != null:
			if a.is_vip:
				status_label.text = "VIP order!"
				# cache vip set value for completion bonus
				vip_set_value = _calc_set_value(a.order_ids)
			else:
				status_label.text = HeroArchetypes.say_order(a.archetype)
				vip_set_value = 0
		else:
			status_label.text = "Order shown!"
			vip_set_value = 0

		_update_need_label()
		_update_recipe_hint()
		_start_bargain_if_needed()
		_try_deliver_current_order()
	)

# -----------------------------
# Orders / VIP generation
# -----------------------------
func _make_order_ids(count: int) -> Array[StringName]:
	if progression.unlocked_orders.is_empty():
		progression.rebuild_unlocked_orders()

	var pool := progression.unlocked_orders
	var out: Array[StringName] = []

	var tries := 0
	while out.size() < count and tries < 200 and not pool.is_empty():
		var id := pool[randi() % pool.size()]
		if not out.has(id):
			out.append(id)
		tries += 1

	if out.is_empty():
		out.append(progression.pick_order_id())

	return out

func _calc_set_value(ids: Array[StringName]) -> int:
	var sum := 0
	for id in ids:
		var it := DataManager.get_item(id)
		sum += it.cost if it != null else 0
	return sum

# -----------------------------
# Archetype pick (day-aware)
# -----------------------------
func _pick_archetype() -> int:
	if day_mod == null:
		return HeroArchetypes.pick()
	return DayModifiers.pick_archetype(day_mod)

# -----------------------------
# Craft tables / shelf
# -----------------------------
func _collect_craft_areas() -> void:
	craft_areas.clear()
	for child in craft_row.get_children():
		var area := child as CraftArea
		if area != null:
			craft_areas.append(area)

	for area in craft_areas:
		area.changed.connect(_on_craft_changed)

func _apply_tables() -> void:
	var n := upgrades.active_table_count(craft_areas.size())
	for i in range(craft_areas.size()):
		craft_areas[i].set_enabled(i < n)

func _build_shelf() -> void:
	for c in shelf_flow.get_children():
		c.queue_free()
	shelf_items.clear()

	var shelf_item_scene := preload("res://scenes/ui/shelf_item.tscn")

	for id in shelf_ids:
		var def := DataManager.get_item(id)
		if def == null:
			continue
		if def.tier > progression.shop_level:
			continue

		var node := shelf_item_scene.instantiate() as ShelfItem
		node.item = def
		shelf_flow.add_child(node)
		shelf_items.append(node)

func _update_shelf_badges() -> void:
	for shelf in shelf_items:
		if shelf != null:
			if shelf.has_method("refresh"):
				shelf.refresh()
			else:
				shelf._apply_view()

# -----------------------------
# Delivery / Need label
# -----------------------------
func _update_need_label() -> void:
	if phase != GamePhase.DAY_ACTIVE or not customer_queue.is_order_visible():
		need_label.text = "Need: (hidden)"
		return

	var active := customer_queue.get_active()
	if active == null:
		need_label.text = "Need: ?"
		return

	if active.is_vip:
		var names: Array[String] = []
		for id in active.order_ids:
			var it := DataManager.get_item(id)
			names.append(_safe_name(it) if it else String(id))
		need_label.text = "VIP items: " + ", ".join(names)
		return

	# normal: show recipe breakdown of the single requested item
	if active.order_ids.is_empty():
		need_label.text = "Need: ?"
		return

	var id0 := active.order_ids[0]
	var r := DataManager.get_recipe(id0)
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
	if phase != GamePhase.DAY_ACTIVE:
		return
	_try_deliver_current_order()
	_update_shelf_badges()
	_update_recipe_hint()

func _try_deliver_current_order() -> void:
	if phase != GamePhase.DAY_ACTIVE or not customer_queue.is_order_visible():
		return

	var active := customer_queue.get_active()
	if active == null:
		return

	# find any deliverable id from the list on any table
	var delivered_id: StringName = StringName()
	var delivered_area: CraftArea = null

	for id in active.order_ids:
		for area in craft_areas:
			if area.has_item(id):
				delivered_id = id
				delivered_area = area
				break
		if delivered_area != null:
			break

	if delivered_area == null:
		return

	# remove from table
	delivered_area.remove_one(delivered_id, false)

	# compute base item value
	var result := DataManager.get_item(delivered_id)
	var base_gold := result.cost if result else 0

	# combo
	if active.serve_time <= FAST_TIME:
		combo += 1
	else:
		combo = 0

	var bonus_mult := 1.0 + float(combo) * 0.05
	var pay_mult := HeroArchetypes.pay_mult(active.archetype)
	var deal_mult := bargain_discount_mult if bargain_active else 1.0

	# tips (only if fast)
	var tip := 0
	if active.serve_time <= FAST_TIME and randf() < HeroArchetypes.tip_chance(active.archetype):
		tip = int(round(float(base_gold) * HeroArchetypes.tip_mult(active.archetype)))

	var total := int(round(float(base_gold) * pay_mult * bonus_mult * deal_mult * _day_pay_mult())) + tip
	gold += total

	# remove from list
	active.order_ids.erase(delivered_id)

	day_served += 1
	day_best_combo = max(day_best_combo, combo)

	# VIP completion bonus
	if active.is_vip and active.order_ids.is_empty():
		var set_bonus := int(round(float(vip_set_value) * VIP_SET_BONUS_MULT))
		gold += set_bonus
		status_label.text = "VIP complete! +" + str(set_bonus)
		vip_set_value = 0
		_reset_bargain()
		customer_queue.complete_active_order()
	else:
		status_label.text = "Delivered!"
		# if non-VIP and this was the only item -> complete order
		if (not active.is_vip) and active.order_ids.is_empty():
			_reset_bargain()
			customer_queue.complete_active_order()

	# progression (kept per-delivery for now)
	progression.on_delivered()

	# deliver chain if next items already ready
	call_deferred("_try_deliver_current_order")

# -----------------------------
# Bargain (HAGGLER only, not VIP)
# -----------------------------
func _reset_bargain() -> void:
	bargain_active = false
	bargain_discount_mult = 1.0
	bargain_patience_bonus = 0.0
	bargain_row.visible = false

func _start_bargain_if_needed() -> void:
	_reset_bargain()

	var a := customer_queue.get_active()
	if a == null:
		return
	if a.is_vip:
		return
	if a.archetype != HeroArchetypes.Type.HAGGLER:
		return

	# chance (set to 0.7)
	if randf() > 0.7:
		return

	bargain_active = true
	bargain_discount_mult = 0.85   # -15% gold
	bargain_patience_bonus = 0.25  # +25% patience

	bargain_label.text = "Deal? -15% gold, +25% patience"
	bargain_row.visible = true

func _accept_bargain() -> void:
	if not bargain_active:
		return
	if phase != GamePhase.DAY_ACTIVE:
		return

	var a := customer_queue.get_active()
	if a != null and customer_queue.is_order_visible():
		var add := a.serve_patience_max * bargain_patience_bonus
		a.serve_patience_max += add
		a.serve_patience += add

	status_label.text = "Deal."
	bargain_row.visible = false

func _reject_bargain() -> void:
	if not bargain_active:
		return
	status_label.text = "No deal."
	_reset_bargain()

# -----------------------------
# Upgrades / Stock actions (break only)
# -----------------------------
func _on_restock_pressed() -> void:
	if phase != GamePhase.DAY_BREAK:
		status_label.text = "Restock only in break"
		return

	var types := DataManager.stock_max_by_id.size()
	var cost := RESTOCK_COST_PER_TYPE * types
	if gold < cost:
		status_label.text = "Not enough gold!"
		return

	gold -= cost
	DataManager.restock_all()
	status_label.text = "Restocked!"
	_update_shelf_badges()
	_save_game()

func _buy_more_tables() -> void:
	if phase != GamePhase.DAY_BREAK:
		status_label.text = "Upgrades only in break"
		return
	if upgrades.active_table_count(craft_areas.size()) >= craft_areas.size():
		status_label.text = "Max tables"
		return
	var cost := upgrades.cost_more_tables()
	if gold < cost:
		status_label.text = "Not enough gold!"
		return
	gold -= cost
	upgrades.inc_tables()
	_apply_tables()
	_refresh_upgrades_ui()
	_save_game()

func _buy_more_stock() -> void:
	if phase != GamePhase.DAY_BREAK:
		status_label.text = "Upgrades only in break"
		return
	var cost := upgrades.cost_more_stock()
	if gold < cost:
		status_label.text = "Not enough gold!"
		return
	gold -= cost
	upgrades.inc_stock()
	DataManager.add_stock_capacity_bonus(10)
	_refresh_upgrades_ui()
	_update_shelf_badges()
	_save_game()

func _buy_replenish() -> void:
	if phase != GamePhase.DAY_BREAK:
		status_label.text = "Upgrades only in break"
		return
	var cost := upgrades.cost_replenish()
	if gold < cost:
		status_label.text = "Not enough gold!"
		return
	gold -= cost
	upgrades.inc_replenish()
	_refresh_upgrades_ui()
	_save_game()

func _buy_more_patience() -> void:
	if phase != GamePhase.DAY_BREAK:
		status_label.text = "Upgrades only in break"
		return
	var cost := upgrades.cost_more_patience()
	if gold < cost:
		status_label.text = "Not enough gold!"
		return
	gold -= cost
	upgrades.inc_patience()
	_refresh_upgrades_ui()
	_save_game()

func _refresh_upgrades_ui() -> void:
	btn_more_tables.text = "More tables (%d/%d) - %dg" % [
		upgrades.active_table_count(craft_areas.size()),
		craft_areas.size(),
		upgrades.cost_more_tables()
	]
	btn_more_stock.text = "Bigger stock (lvl %d) - %dg" % [upgrades.stock_level, upgrades.cost_more_stock()]
	btn_replenish.text = "Better supply (lvl %d) - %dg" % [upgrades.replenish_level, upgrades.cost_replenish()]
	btn_more_patience.text = "More patience (lvl %d) - %dg" % [upgrades.patience_level, upgrades.cost_more_patience()]

# -----------------------------
# UI
# -----------------------------
func _update_ui() -> void:
	day_label.text = "Day: %d" % day_index

	var day_left_sec = max(0.0, day_time_left) if phase == GamePhase.DAY_ACTIVE else 0.0
	var sec := int(day_left_sec) % 60
	var min := int(day_left_sec) / 60
	day_timer_label.text = "%02d:%02d" % [min, sec]

	gold_label.text = "Gold: %d" % gold
	combo_label.text = "Combo: %d" % combo
	level_label.text = "Level: %d" % progression.shop_level
	preps_label.text = "Preps: %d" % preps.size()
	var active := customer_queue.get_active()
	if phase != GamePhase.DAY_ACTIVE or active == null:
		order_label.text = "Order: -"
		patience_bar.value = 0
		mood_label.text = "-"
	else:
		if not customer_queue.is_order_visible():
			order_label.text = "Order: (hidden)"
			patience_bar.value = 100
			mood_label.text = "..."
		else:
			if active.is_vip:
				order_label.text = "VIP: %d items" % active.order_ids.size()
			else:
				var id0 := active.order_ids[0] if not active.order_ids.is_empty() else StringName()
				var it := DataManager.get_item(id0)
				order_label.text = "Order: " + (_safe_name(it) if it else String(id0))

			var patience_ratio = clamp(active.serve_patience / active.serve_patience_max, 0.0, 1.0)
			patience_bar.value = patience_ratio * 100.0
			mood_label.text = "OK" if patience_ratio > MOOD_OK else ("WARN" if patience_ratio > MOOD_WARN else "ANGRY")

	# queue display
	var q: Array[String] = []
	if phase == GamePhase.DAY_ACTIVE:
		for c in customer_queue.get_queue():
			var queue_ratio = clamp(c.queue_patience / c.queue_patience_max, 0.0, 1.0)
			q.append(str(int(round(queue_ratio * 100.0))) + "%")
	queue_label.text = "Queue: " + ", ".join(q)

# -----------------------------
# Utils
# -----------------------------
func _safe_name(it: ItemDef) -> String:
	if it == null:
		return "?"
	var key := String(it.name_key)
	var s := tr(key)
	return s if s != key else String(it.id)

func _enable_workshop_tables() -> void:
	# в перерыве даём те же столы, что и в бою (по апгрейду)
	_apply_tables()

func _count_available(id: StringName) -> int:
	var n := 0

	# склад (только если складской)
	if DataManager.is_stocked(id):
		n += DataManager.get_stock(id)

	# заготовки
	for it in preps:
		if it != null and it.id == id:
			n += 1

	# предметы на столах
	for a in craft_areas:
		for it in a.get_items():
			if it != null and it.id == id:
				n += 1

	return n

func _collect_base_requirements(item_id: StringName, req: Dictionary, variant: Dictionary, stack: Array[StringName]) -> void:
	if stack.has(item_id):
		return

	var it := DataManager.get_item(item_id)
	if it == null:
		return

	# базовые/скроллы считаем “то, что надо взять руками”
	if it.type == &"base" or it.type == &"recipe_scroll":
		req[item_id] = int(req.get(item_id, 0)) + 1
		return

	var r := DataManager.get_recipe(item_id)
	if r == null:
		return

	stack.append(item_id)

	for c in r.components:
		if c != null:
			_collect_base_requirements(c.id, req, variant, stack)

	# Вариантные опции: отмечаем как “вариант”
	# (v1: просто подсветим все варианты, без углубления)
	if r.requires_variant:
		for opt in r.variant_options:
			if opt != null:
				variant[opt.id] = true

	stack.pop_back()

func _update_recipe_hint() -> void:
	# сброс подсветки
	for s in shelf_items:
		if s != null:
			s.set_hint_state(ShelfItem.HintState.NONE)

	hint_label.text = ""

	if phase != GamePhase.DAY_ACTIVE or not customer_queue.is_order_visible():
		return

	var active := customer_queue.get_active()
	if active == null:
		return

	# req: base_id -> count, variant: option_id -> true
	var req: Dictionary = {}
	var variant: Dictionary = {}
	var stack: Array[StringName] = []

	# обычный клиент = один item, VIP = несколько
	for id in active.order_ids:
		_collect_base_requirements(id, req, variant, stack)

	# подсветка REQUIRED
	for id in req.keys():
		for s in shelf_items:
			if s != null and s.item != null and s.item.id == id:
				s.set_hint_state(ShelfItem.HintState.REQUIRED)
				break

	# подсветка VARIANT (не перетираем REQUIRED)
	for id in variant.keys():
		for s in shelf_items:
			if s != null and s.item != null and s.item.id == id:
				if s.hint_state == ShelfItem.HintState.NONE:
					s.set_hint_state(ShelfItem.HintState.VARIANT)
				break

	# missing по доступности
	var missing_parts: Array[String] = []
	for id in req.keys():
		var need := int(req[id])
		var have := _count_available(id)
		var miss = max(0, need - have)
		if miss > 0:
			var it := DataManager.get_item(id)
			var name := _safe_name(it) if it != null else String(id)
			missing_parts.append("%s x%d" % [name, miss])

	# собрать текст подсказки
	if not missing_parts.is_empty():
		hint_label.text = "Missing: " + ", ".join(missing_parts)
	else:
		hint_label.text = "Ready to craft"

func _on_clear_pressed() -> void:
	for area in craft_areas:
		area.clear()

func _make_save_dict() -> Dictionary:
	var prep_ids: Array[String] = []
	for it in preps:
		if it != null:
			prep_ids.append(String(it.id))

	return {
		"v": 1,
		"gold": gold,
		"day_index": day_index,

		"upg": {
			"tables": upgrades.tables_level,
			"stock": upgrades.stock_level,
			"replenish": upgrades.replenish_level,
			"patience": upgrades.patience_level,
		},

		"prog": {
			"level": progression.shop_level,
			"deliveries": progression.deliveries,
		},

		"stock": DataManager.get_stock_state(),
		"preps": prep_ids,
	}

func _apply_save_dict(s: Dictionary) -> void:
	if s.is_empty():
		return

	gold = int(s.get("gold", gold))
	day_index = int(s.get("day_index", day_index))

	var u = s.get("upg", {})
	if typeof(u) == TYPE_DICTIONARY:
		upgrades.tables_level = int(u.get("tables", upgrades.tables_level))
		upgrades.stock_level = int(u.get("stock", upgrades.stock_level))
		upgrades.replenish_level = int(u.get("replenish", upgrades.replenish_level))
		upgrades.patience_level = int(u.get("patience", upgrades.patience_level))

	# ВАЖНО: stock_level влияет на max склада в DataManager
	if upgrades.stock_level > 0:
		DataManager.add_stock_capacity_bonus(10 * upgrades.stock_level)

	var p = s.get("prog", {})
	if typeof(p) == TYPE_DICTIONARY:
		progression.shop_level = int(p.get("level", progression.shop_level))
		progression.deliveries = int(p.get("deliveries", progression.deliveries))
		progression.rebuild_unlocked_orders()

	var st = s.get("stock", {})
	if typeof(st) == TYPE_DICTIONARY:
		DataManager.set_stock_state(st)

	# preps: восстанавливаем по id, базу (если вдруг попала) возвращаем на склад
	preps.clear()
	var pr = s.get("preps", [])
	if pr is Array:
		for x in pr:
			var id := StringName(String(x))
			var it := DataManager.get_item(id)
			if it == null:
				continue
			if DataManager.is_stocked(it.id):
				DataManager.add_stock(it.id, 1)
			else:
				preps.append(it)

	# применяем эффекты на сцену
	_apply_tables()
	_build_shelf()
	_update_shelf_badges()
	_refresh_upgrades_ui()

func _save_game() -> void:
	SaveManager.save_dict(_make_save_dict())

func _load_game() -> void:
	_apply_save_dict(SaveManager.load_dict())
