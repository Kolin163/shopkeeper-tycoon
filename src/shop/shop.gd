# res://src/shop/shop_controller.gd
# Desktop-only controller (logic) for UI v2 modules + UIRoot.
# Assumes your scene has:
#   - Node (root) / or any parent
#     - UIRoot (res://scenes/ui/ui_root.tscn)
#
# And UIRoot exposes:
#   shelf_ui: ShelfCatalogUI
#   workbench_ui: WorkbenchUI
#   top_bar_ui: TopBarUI
#   order_ui: OrderUI
#   log_ui: LogUI (optional)
#   break_modal: DayBreakModal
#   end_modal: EndDayModal
#   upgrades_modal: UpgradesModal
#   show_modal(name), hide_modals()

extends Node
class_name ShopController

enum GamePhase { DAY_BREAK, DAY_ACTIVE, DAY_END }

const DAY_LENGTH := 180.0
const QUEUE_SIZE := 3
const APPROACH_TIME := 0.7
const ANNOUNCE_TIME := 0.4
const QUEUE_DRAIN_MULT := 0.25

const FAST_TIME := 4.0
const MOOD_OK := 0.66
const MOOD_WARN := 0.33

const PREPS_PER_TABLE_LIMIT := 8

const RESTOCK_COST_PER_TYPE := 50
const VIP_SET_BONUS_MULT := 0.20

@onready var ui_root: UIRoot = $UIRoot

var top_ui: TopBarUI
var order_ui: OrderUI
var shelf_ui: ShelfCatalogUI
var workbench_ui: WorkbenchUI

var phase: int = GamePhase.DAY_BREAK
var day_index := 0
var day_time_left := 0.0

# day stats
var day_served := 0
var day_left := 0
var day_best_combo := 0
var day_gold_start := 0

var gold := 0
var combo := 0

var upgrades := Upgrades.new()
var progression := Progression.new()
var customer_queue := CustomerQueue.new()

var day_mod: DayModifier = null

# VIP completion bonus uses cached set value
var vip_set_value := 0

# preps (non-stock items)
var preps: Array[ItemDef] = []

# favorites
var fav_ids: Dictionary = {} # StringName -> true

# bargain state
var bargain_active := false
var bargain_discount_mult := 1.0
var bargain_patience_bonus := 0.0
var bargain_text := "Deal? -15% gold, +25% patience"

# UI text buffers
var ui_status_text := ""
var ui_hint_text := "" # keep empty if you don't need hints
var ui_need_text := ""

# content pools (for now you can keep small; later build from JSON)
var order_pool: Array[StringName] = [
	&"magic_wand",
	&"power_treads",
	&"tranquil_boots",
]

var _customer_signals_connected := false

func _ready() -> void:
	randomize()

	# grab modules from UIRoot
	top_ui = ui_root.top_bar_ui
	order_ui = ui_root.order_ui
	shelf_ui = ui_root.shelf_ui
	workbench_ui = ui_root.workbench_ui

	if top_ui == null or order_ui == null or shelf_ui == null or workbench_ui == null:
		push_error("UI modules missing. Check UIRoot exports and slots.")
		return

	_connect_ui_signals()
	_connect_customer_signals_once()

	# progression setup (shelf_ids no longer used for availability; pass empty)
	progression.setup(order_pool, [])
	progression.level_changed.connect(func(_lvl: int) -> void:
		shelf_ui.rebuild(progression.shop_level, fav_ids)
		shelf_ui.refresh_stock()
		_refresh_upgrades_ui()
	)

	_load_game()

	# build shelf once (categories already prepared inside ShelfCatalogUI._ready)
	shelf_ui.rebuild(progression.shop_level, fav_ids)
	shelf_ui.refresh_stock()

	# start in break WITHOUT night supply on boot
	_go_to_break(false)

func _process(delta: float) -> void:
	if phase == GamePhase.DAY_ACTIVE:
		day_time_left -= delta
		customer_queue.update(delta)
		if day_time_left <= 0.0:
			_end_day()

	_update_ui()

# -------------------------
# UI wiring
# -------------------------
func _connect_ui_signals() -> void:
	# TopBar buttons
	top_ui.restock_pressed.connect(_on_restock_pressed)
	top_ui.upgrades_pressed.connect(func():
		if phase != GamePhase.DAY_BREAK:
			_toast("Upgrades only in break")
			return
		ui_root.show_modal("upgrades")
		_refresh_upgrades_ui()
	)

	# Order buttons
	order_ui.clear_pressed.connect(_on_clear_pressed)
	order_ui.deal_pressed.connect(_accept_bargain)
	order_ui.no_deal_pressed.connect(_reject_bargain)

	# Shelf catalog events
	shelf_ui.filters_changed.connect(func():
		shelf_ui.rebuild(progression.shop_level, fav_ids)
	)
	shelf_ui.fav_changed.connect(_on_shelf_fav_changed)

	# Workbench changes
	workbench_ui.changed.connect(_on_workbench_changed)

	# Modals
	if ui_root.break_modal:
		ui_root.break_modal.start_day_pressed.connect(_start_day)
		if ui_root.break_modal.has_signal("upgrades_pressed"):
			ui_root.break_modal.upgrades_pressed.connect(func():
				ui_root.show_modal("upgrades")
				_refresh_upgrades_ui()
			)

	if ui_root.end_modal:
		ui_root.end_modal.continue_pressed.connect(func():
			_go_to_break(true)
		)

	if ui_root.upgrades_modal:
		ui_root.upgrades_modal.close_pressed.connect(func():
			ui_root.show_modal("break")
		)
		ui_root.upgrades_modal.buy_tables.connect(_buy_more_tables)
		ui_root.upgrades_modal.buy_stock.connect(_buy_more_stock)
		ui_root.upgrades_modal.buy_replenish.connect(_buy_replenish)
		ui_root.upgrades_modal.buy_patience.connect(_buy_more_patience)

func _toast(text: String, ttl: float = 3.0) -> void:
	# log feed (preferred)
	if ui_root != null and ui_root.log_ui != null:
		ui_root.log_ui.push(text, ttl)
	# keep a short status too (order_ui shows it)
	ui_status_text = text

func _on_shelf_fav_changed(item_id: StringName, is_fav: bool) -> void:
	if is_fav:
		fav_ids[item_id] = true
	else:
		fav_ids.erase(item_id)

	shelf_ui.rebuild(progression.shop_level, fav_ids)
	_save_game()

func _on_workbench_changed() -> void:
	if phase != GamePhase.DAY_ACTIVE:
		# in break we still want stock UI to update
		shelf_ui.refresh_stock()
		return

	_try_deliver_current_order()
	shelf_ui.refresh_stock()

# -------------------------
# Day flow
# -------------------------
func _start_day() -> void:
	phase = GamePhase.DAY_ACTIVE
	day_index += 1
	day_time_left = DAY_LENGTH

	day_mod = DayModifiers.pick()
	_toast("Day started!")

	# reset day stats
	day_served = 0
	day_left = 0
	day_best_combo = 0
	day_gold_start = gold
	combo = 0

	_reset_bargain()

	ui_root.hide_modals()

	# enable tables
	_enable_workshop_tables()

	# collect anything crafted during break into stock/preps
	_collect_tables_to_stock_and_preps()
	shelf_ui.refresh_stock()

	# clear tables for day start
	workbench_ui.clear_all_silent()

	# place preps
	_place_preps_on_tables()

	# VIP every 3rd day
	var vip_order_count := 0
	if day_index % 3 == 0:
		vip_order_count = 2 + (randi() % 2)

	customer_queue.setup(
		Callable(self, "_make_order_ids"),
		Callable(self, "_pick_archetype"),
		Callable(self, "_serve_patience_max_for_day"),
		vip_order_count,
		QUEUE_SIZE, APPROACH_TIME, ANNOUNCE_TIME,
		QUEUE_DRAIN_MULT * _day_queue_drain_mult()
	)

	ui_root.hide_modals()

func _end_day() -> void:
	if phase != GamePhase.DAY_ACTIVE:
		return

	phase = GamePhase.DAY_END

	# collect items -> stock/preps
	_collect_tables_to_stock_and_preps()
	shelf_ui.refresh_stock()

	# disable tables
	workbench_ui.set_active_tables(0)

	var profit := gold - day_gold_start
	var summary := "Day %d results:\nServed: %d\nLeft: %d\nBest combo: %d\nProfit: %d" % [
		day_index, day_served, day_left, day_best_combo, profit
	]

	if ui_root.end_modal:
		ui_root.end_modal.set_summary(summary)
	ui_root.show_modal("end")

	_toast("Day ended!")
	_save_game()

func _go_to_break(apply_night_supply: bool = true) -> void:
	phase = GamePhase.DAY_BREAK

	_enable_workshop_tables()
	ui_root.show_modal("break")

	if apply_night_supply and day_index > 0:
		_apply_night_supply()
		shelf_ui.refresh_stock()

	_refresh_upgrades_ui()
	_save_game()

# -------------------------
# Night supply (Approach 2)
# -------------------------
func _night_supply_amount() -> int:
	var base := 2 + upgrades.replenish_level
	var mult := day_mod.night_supply_mult if day_mod != null else 1.0
	return max(0, int(round(float(base) * mult)))

func _apply_night_supply() -> void:
	var amount := _night_supply_amount()
	DataManager.replenish_tick(amount)
	_toast("Night supply: +%d each" % amount)

# -------------------------
# Day modifiers helpers
# -------------------------
func _day_patience_mult() -> float:
	return day_mod.patience_mult if day_mod != null else 1.0

func _day_pay_mult() -> float:
	return day_mod.pay_mult if day_mod != null else 1.0

func _day_queue_drain_mult() -> float:
	return day_mod.queue_drain_mult if day_mod != null else 1.0

func _serve_patience_max_for_day() -> float:
	return upgrades.serve_patience_max() * _day_patience_mult()

# -------------------------
# CustomerQueue signals
# -------------------------
func _connect_customer_signals_once() -> void:
	if _customer_signals_connected:
		return
	_customer_signals_connected = true

	customer_queue.active_promoted.connect(func() -> void:
		if phase == GamePhase.DAY_ACTIVE:
			_reset_bargain()
			ui_need_text = _build_need_text()
			_toast("Customer approaching...", 1.2)
	)

	customer_queue.queue_customer_left.connect(func() -> void:
		if phase == GamePhase.DAY_ACTIVE:
			combo = 0
			day_left += 1
			_toast("Someone left the queue!", 2.0)
	)

	customer_queue.active_customer_left.connect(func() -> void:
		if phase == GamePhase.DAY_ACTIVE:
			combo = 0
			day_left += 1
			_reset_bargain()
			_toast("Customer left!", 2.0)
	)

	customer_queue.order_shown.connect(func(_id: StringName) -> void:
		if phase != GamePhase.DAY_ACTIVE:
			return

		var a := customer_queue.get_active()
		if a != null:
			if a.is_vip:
				vip_set_value = _calc_set_value(a.order_ids)
				_toast("VIP order!", 2.0)
			else:
				vip_set_value = 0
				_toast(HeroArchetypes.say_order(a.archetype), 2.0)

		ui_need_text = _build_need_text()
		_start_bargain_if_needed()
		_try_deliver_current_order()
	)

# -------------------------
# Orders / VIP generation
# -------------------------
func _make_order_ids(count: int) -> Array[StringName]:
	# relies on Progression.unlocked_orders
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

# -------------------------
# Archetype pick (day-aware)
# -------------------------
func _pick_archetype() -> int:
	if day_mod == null:
		return HeroArchetypes.pick()
	return DayModifiers.pick_archetype(day_mod)

# -------------------------
# Workbench / preps
# -------------------------
func _enable_workshop_tables() -> void:
	_apply_tables()

func _apply_tables() -> void:
	var total := workbench_ui.craft_areas.size()
	var n := upgrades.active_table_count(total)
	workbench_ui.set_active_tables(n)

func _collect_tables_to_stock_and_preps() -> void:
	var taken := workbench_ui.take_all_items()
	for it in taken:
		if it == null:
			continue
		if DataManager.is_stocked(it.id):
			DataManager.add_stock(it.id, 1)
		else:
			preps.append(it)

func _place_preps_on_tables() -> void:
	if preps.is_empty():
		return

	var idx := 0
	for a in workbench_ui.craft_areas:
		if not a.enabled:
			continue
		while idx < preps.size() and a.get_items().size() < PREPS_PER_TABLE_LIMIT:
			a.put_items([preps[idx]], true)
			idx += 1

	if idx > 0:
		preps = preps.slice(idx)

# -------------------------
# Delivery / need text
# -------------------------
func _build_need_text() -> String:
	if phase != GamePhase.DAY_ACTIVE or not customer_queue.is_order_visible():
		return "Need: (hidden)"

	var active := customer_queue.get_active()
	if active == null:
		return "Need: ?"

	if active.is_vip:
		var names: Array[String] = []
		for id in active.order_ids:
			var it := DataManager.get_item(id)
			names.append(_safe_name(it) if it else String(id))
		return "VIP items: " + ", ".join(names)

	# normal: show recipe breakdown for the first item
	if active.order_ids.is_empty():
		return "Need: ?"

	var id0 := active.order_ids[0]
	var r := DataManager.get_recipe(id0)
	if r == null:
		return "Need: ?"

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

	return "Need: " + " + ".join(parts)

func _try_deliver_current_order() -> void:
	if phase != GamePhase.DAY_ACTIVE or not customer_queue.is_order_visible():
		return

	var active := customer_queue.get_active()
	if active == null:
		return

	var delivered_id: StringName = StringName()
	var delivered_area: CraftArea = null

	for id in active.order_ids:
		for area in workbench_ui.craft_areas:
			if area.has_item(id):
				delivered_id = id
				delivered_area = area
				break
		if delivered_area != null:
			break

	if delivered_area == null:
		return

	delivered_area.remove_one(delivered_id, false)

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

	var tip := 0
	if active.serve_time <= FAST_TIME and randf() < HeroArchetypes.tip_chance(active.archetype):
		tip = int(round(float(base_gold) * HeroArchetypes.tip_mult(active.archetype)))

	var total := int(round(float(base_gold) * pay_mult * bonus_mult * deal_mult * _day_pay_mult())) + tip
	gold += total

	active.order_ids.erase(delivered_id)

	day_served += 1
	day_best_combo = max(day_best_combo, combo)

	if active.is_vip and active.order_ids.is_empty():
		var set_bonus := int(round(float(vip_set_value) * VIP_SET_BONUS_MULT))
		gold += set_bonus
		vip_set_value = 0
		_reset_bargain()
		customer_queue.complete_active_order()
		_toast("VIP complete! +" + str(set_bonus), 3.0)
	else:
		if (not active.is_vip) and active.order_ids.is_empty():
			_reset_bargain()
			customer_queue.complete_active_order()
		_toast("Delivered!", 1.2)

	progression.on_delivered()
	ui_need_text = _build_need_text()

	call_deferred("_try_deliver_current_order")

# -------------------------
# Bargain
# -------------------------
func _reset_bargain() -> void:
	bargain_active = false
	bargain_discount_mult = 1.0
	bargain_patience_bonus = 0.0

func _start_bargain_if_needed() -> void:
	_reset_bargain()

	var a := customer_queue.get_active()
	if a == null:
		return
	if a.is_vip:
		return
	if a.archetype != HeroArchetypes.Type.HAGGLER:
		return

	if randf() > 0.7:
		return

	bargain_active = true
	bargain_discount_mult = 0.85
	bargain_patience_bonus = 0.25

func _accept_bargain() -> void:
	if not bargain_active or phase != GamePhase.DAY_ACTIVE:
		return

	var a := customer_queue.get_active()
	if a != null and customer_queue.is_order_visible():
		var add := a.serve_patience_max * bargain_patience_bonus
		a.serve_patience_max += add
		a.serve_patience += add

	_toast("Deal.", 1.2)

func _reject_bargain() -> void:
	if not bargain_active:
		return
	_toast("No deal.", 1.2)
	_reset_bargain()

# -------------------------
# Buttons (restock/clear/upgrades)
# -------------------------
func _on_clear_pressed() -> void:
	# clear all craft areas (does not refund stock)
	for a in workbench_ui.craft_areas:
		a.clear()

func _on_restock_pressed() -> void:
	if phase != GamePhase.DAY_BREAK:
		_toast("Restock only in break", 2.0)
		return

	var types := DataManager.stock_max_by_id.size()
	var cost := RESTOCK_COST_PER_TYPE * types
	if gold < cost:
		_toast("Not enough gold!", 2.0)
		return

	gold -= cost
	DataManager.restock_all()
	shelf_ui.refresh_stock()
	_toast("Restocked!", 2.0)
	_save_game()

# -------------------------
# Upgrades
# -------------------------
func _buy_more_tables() -> void:
	if phase != GamePhase.DAY_BREAK:
		_toast("Upgrades only in break", 2.0)
		return
	var total := workbench_ui.craft_areas.size()
	if upgrades.active_table_count(total) >= total:
		_toast("Max tables", 2.0)
		return

	var cost := upgrades.cost_more_tables()
	if gold < cost:
		_toast("Not enough gold!", 2.0)
		return

	gold -= cost
	upgrades.inc_tables()
	_apply_tables()
	_refresh_upgrades_ui()
	_save_game()

func _buy_more_stock() -> void:
	if phase != GamePhase.DAY_BREAK:
		_toast("Upgrades only in break", 2.0)
		return
	var cost := upgrades.cost_more_stock()
	if gold < cost:
		_toast("Not enough gold!", 2.0)
		return

	gold -= cost
	upgrades.inc_stock()
	DataManager.add_stock_capacity_bonus(10)
	shelf_ui.refresh_stock()
	_refresh_upgrades_ui()
	_save_game()

func _buy_replenish() -> void:
	if phase != GamePhase.DAY_BREAK:
		_toast("Upgrades only in break", 2.0)
		return
	var cost := upgrades.cost_replenish()
	if gold < cost:
		_toast("Not enough gold!", 2.0)
		return

	gold -= cost
	upgrades.inc_replenish()
	_refresh_upgrades_ui()
	_save_game()

func _buy_more_patience() -> void:
	if phase != GamePhase.DAY_BREAK:
		_toast("Upgrades only in break", 2.0)
		return
	var cost := upgrades.cost_more_patience()
	if gold < cost:
		_toast("Not enough gold!", 2.0)
		return

	gold -= cost
	upgrades.inc_patience()
	_refresh_upgrades_ui()
	_save_game()

func _refresh_upgrades_ui() -> void:
	if ui_root.upgrades_modal == null:
		return

	var total := workbench_ui.craft_areas.size()
	var t_tables := "More tables (%d/%d) - %dg" % [upgrades.active_table_count(total), total, upgrades.cost_more_tables()]
	var t_stock := "Bigger stock (lvl %d) - %dg" % [upgrades.stock_level, upgrades.cost_more_stock()]
	var t_repl := "Better supply (lvl %d) - %dg" % [upgrades.replenish_level, upgrades.cost_replenish()]
	var t_pat := "More patience (lvl %d) - %dg" % [upgrades.patience_level, upgrades.cost_more_patience()]

	ui_root.upgrades_modal.set_texts(t_tables, t_stock, t_repl, t_pat)

# -------------------------
# UI update
# -------------------------
func _update_ui() -> void:
	var day_mod_text := ""
	if day_mod != null:
		day_mod_text = "%s: %s" % [day_mod.title, day_mod.desc]

	top_ui.set_data(
		day_index,
		day_time_left if phase == GamePhase.DAY_ACTIVE else 0.0,
		day_mod_text,
		gold, combo, progression.shop_level, preps.size()
	)

	# queue
	var q: Array[String] = []
	if phase == GamePhase.DAY_ACTIVE:
		for c in customer_queue.get_queue():
			var ratio = clamp(c.queue_patience / c.queue_patience_max, 0.0, 1.0)
			q.append(str(int(round(ratio * 100.0))) + "%")
	var queue_text := "Queue: " + ", ".join(q)

	# order display
	var order_text := "Order: -"
	var patience_ratio := 0.0
	var mood_text := "-"
	var need_text := ""

	var active := customer_queue.get_active()
	if phase == GamePhase.DAY_ACTIVE and active != null:
		if not customer_queue.is_order_visible():
			order_text = "Order: (hidden)"
			patience_ratio = 1.0
			mood_text = "..."
			need_text = "Need: (hidden)"
		else:
			if active.is_vip:
				order_text = "VIP: %d items" % active.order_ids.size()
			else:
				var id0 := active.order_ids[0] if not active.order_ids.is_empty() else StringName()
				var it := DataManager.get_item(id0)
				order_text = "Order: " + (_safe_name(it) if it else String(id0))

			patience_ratio = clamp(active.serve_patience / active.serve_patience_max, 0.0, 1.0)
			mood_text = "OK" if patience_ratio > MOOD_OK else ("WARN" if patience_ratio > MOOD_WARN else "ANGRY")
			need_text = ui_need_text if not ui_need_text.is_empty() else _build_need_text()

	order_ui.set_data(queue_text, order_text, need_text, patience_ratio, mood_text, ui_status_text, ui_hint_text)
	order_ui.show_bargain(bargain_active, bargain_text)

# -------------------------
# Utils
# -------------------------
func _safe_name(it: ItemDef) -> String:
	if it == null:
		return "?"
	var key := String(it.name_key)
	var s := tr(key)
	return s if s != key else String(it.id)

# -------------------------
# Saves
# -------------------------
func _make_save_dict() -> Dictionary:
	var prep_ids: Array[String] = []
	for it in preps:
		if it != null:
			prep_ids.append(String(it.id))

	var fav_list: Array[String] = []
	for k in fav_ids.keys():
		fav_list.append(String(k))

	return {
		"v": 1,
		"gold": gold,
		"day_index": day_index,
		"fav": fav_list,
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

	# favorites
	fav_ids.clear()
	var fav = s.get("fav", [])
	if fav is Array:
		for x in fav:
			fav_ids[StringName(String(x))] = true

	# upgrades
	var u = s.get("upg", {})
	if typeof(u) == TYPE_DICTIONARY:
		upgrades.tables_level = int(u.get("tables", upgrades.tables_level))
		upgrades.stock_level = int(u.get("stock", upgrades.stock_level))
		upgrades.replenish_level = int(u.get("replenish", upgrades.replenish_level))
		upgrades.patience_level = int(u.get("patience", upgrades.patience_level))

	# apply stock capacity bonus from upgrade once
	if upgrades.stock_level > 0:
		DataManager.add_stock_capacity_bonus(10 * upgrades.stock_level)

	# progression
	var p = s.get("prog", {})
	if typeof(p) == TYPE_DICTIONARY:
		progression.shop_level = maxi(1, int(p.get("level", progression.shop_level)))
		progression.deliveries = maxi(0, int(p.get("deliveries", progression.deliveries)))
		progression.rebuild_unlocked_orders()

	# stock
	var st = s.get("stock", {})
	if typeof(st) == TYPE_DICTIONARY:
		DataManager.set_stock_state(st)

	# preps
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

	_apply_tables()
	shelf_ui.rebuild(progression.shop_level, fav_ids)
	shelf_ui.refresh_stock()
	_refresh_upgrades_ui()

func _save_game() -> void:
	SaveManager.save_dict(_make_save_dict())

func _load_game() -> void:
	_apply_save_dict(SaveManager.load_dict())
