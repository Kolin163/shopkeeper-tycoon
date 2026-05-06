extends Control

@onready var db_label: Label = $VBoxContainer/DbLabel
@onready var gold_label: Label = $VBoxContainer/TopBar/GoldLabel
@onready var combo_label: Label = $VBoxContainer/TopBar/ComboLabel
@onready var level_label: Label = $VBoxContainer/TopBar/LevelLabel
@onready var day_mod_label: Label = $VBoxContainer/TopBar/DayModLabel

@onready var restock_button: Button = $VBoxContainer/TopBar/RestockButton
@onready var upgrades_button: Button = $VBoxContainer/TopBar/UpgradesButton

@onready var queue_label: Label = $VBoxContainer/OrderBar/QueueLabel
@onready var order_label: Label = $VBoxContainer/OrderBar/OrderLabel
@onready var need_label: Label = $VBoxContainer/OrderBar/NeedLabel
@onready var status_label: Label = $VBoxContainer/OrderBar/StatusLabel
@onready var clear_button: Button = $VBoxContainer/OrderBar/ClearButton
@onready var patience_bar: ProgressBar = $VBoxContainer/OrderBar/PatienceBar
@onready var mood_label: Label = $VBoxContainer/OrderBar/MoodLabel

@onready var craft_row: HBoxContainer = $VBoxContainer/CraftRow
@onready var shelf_flow: Control = $VBoxContainer/ShelfFlow

@onready var upgrades_panel: PanelContainer = $VBoxContainer/UpgradesPanel
@onready var btn_more_tables: Button = $VBoxContainer/UpgradesPanel/VBoxContainer/BtnMoreTables
@onready var btn_more_stock: Button = $VBoxContainer/UpgradesPanel/VBoxContainer/BtnMoreStock
@onready var btn_replenish: Button = $VBoxContainer/UpgradesPanel/VBoxContainer/BtnReplenish
@onready var btn_more_patience: Button = $VBoxContainer/UpgradesPanel/VBoxContainer/BtnMorePatience
@onready var btn_close_upgrades: Button = $VBoxContainer/UpgradesPanel/VBoxContainer/BtnCloseUpgrades

@onready var bargain_row: HBoxContainer = $VBoxContainer/OrderBar/BargainRow
@onready var bargain_label: Label = $VBoxContainer/OrderBar/BargainRow/BargainLabel
@onready var btn_deal: Button = $VBoxContainer/OrderBar/BargainRow/BtnDeal
@onready var btn_no_deal: Button = $VBoxContainer/OrderBar/BargainRow/BtnNoDeal

@onready var day_label: Label = $VBoxContainer/TopBar/DayLabel
@onready var day_timer_label: Label = $VBoxContainer/TopBar/DayTimerLabel

@onready var day_break_panel: PanelContainer = $VBoxContainer/DayBreakPanel
@onready var start_day_button: Button = $VBoxContainer/DayBreakPanel/VBoxContainer/StartDayButton

@onready var end_day_panel: PanelContainer = $VBoxContainer/EndDayPanel
@onready var end_summary_label: Label = $VBoxContainer/EndDayPanel/VBoxContainer/EndSummaryLabel
@onready var to_break_button: Button = $VBoxContainer/EndDayPanel/VBoxContainer/ToBreakButton

const FAST_TIME := 4.0
const MOOD_OK := 0.66
const MOOD_WARN := 0.33
const RESTOCK_COST_PER_TYPE := 50

const QUEUE_SIZE := 3
const APPROACH_TIME := 0.7
const ANNOUNCE_TIME := 0.4
const QUEUE_DRAIN_MULT := 0.25

var craft_areas: Array[CraftArea] = []
var shelf_items: Array[ShelfItem] = []

var gold := 0
var combo := 0
var replenish_timer: Timer

var bargain_active := false
var bargain_discount_mult := 1.0
var bargain_patience_bonus := 0.0

# Данные (пока руками)
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

enum GamePhase { DAY_BREAK, DAY_ACTIVE, DAY_END }

const DAY_LENGTH := 180.0  # 3 минуты (потом подстроишь)

var phase: int = GamePhase.DAY_BREAK
var day_index := 0
var day_time_left := 0.0

# статистика дня
var day_served := 0
var day_left := 0
var day_best_combo := 0
var day_gold_start := 0

# Модели
var upgrades := Upgrades.new()
var progression := Progression.new()
var customer_queue := CustomerQueue.new()
var day_mod: DayModifier = null


func _ready() -> void:
	randomize()

	db_label.text = "%s\nAll recipes: %d" % [DataManager.load_report, DataManager.all_recipes.size()]

	clear_button.text = "Clear"
	clear_button.pressed.connect(_on_clear_pressed)
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

	start_day_button.pressed.connect(_start_day)
	to_break_button.pressed.connect(_go_to_break)

	_go_to_break()  # стартуем в перерыве

	_build_shelf()
	_collect_craft_areas()
	_apply_tables()

	# Прогрессия
	progression.setup(order_pool, shelf_ids)
	progression.level_changed.connect(func(_lvl: int) -> void:
		status_label.text = "Level up! Level: %d" % progression.shop_level
		_build_shelf()
		_update_shelf_badges()
		_refresh_upgrades_ui()
	)

	# Очередь клиентов
	customer_queue.setup(
		Callable(progression, "pick_order_id"),
		Callable(self, "_pick_archetype"),
		Callable(upgrades, "serve_patience_max"),
		QUEUE_SIZE, APPROACH_TIME, ANNOUNCE_TIME, QUEUE_DRAIN_MULT * _day_queue_drain_mult()
	)

	customer_queue.active_promoted.connect(func() -> void:
		status_label.text = "Customer approaching..."
		_update_need_label()
	)

	customer_queue.queue_customer_left.connect(func() -> void:
		status_label.text = "Someone left the queue!"
		combo = 0
		if phase == GamePhase.DAY_ACTIVE:
			day_left += 1
	)

	customer_queue.active_customer_left.connect(func() -> void:
		status_label.text = "Customer left!"
		combo = 0
		if phase == GamePhase.DAY_ACTIVE:
			day_left += 1
		_update_need_label()
	)

	customer_queue.order_shown.connect(func(_id: StringName) -> void:
		var a := customer_queue.get_active()
		if a != null:
			status_label.text = HeroArchetypes.say_order(a.archetype)
			_start_bargain_if_needed()
		else:
			status_label.text = "Order shown!"
		_update_need_label()
		_try_deliver_current_order()
	)

	_update_ui()
	_update_shelf_badges()
	_refresh_upgrades_ui()


func _process(delta: float) -> void:
	if phase == GamePhase.DAY_ACTIVE:
		day_time_left -= delta
		customer_queue.update(delta)

		if day_time_left <= 0.0:
			_end_day()

	_update_ui()


# ---------- init UI ----------

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


# ---------- order / delivery ----------

func _start_day() -> void:
	phase = GamePhase.DAY_ACTIVE
	day_index += 1
	day_mod = DayModifier.pick()
	day_mod_label.text = "%s: %s" % [day_mod.title, day_mod.desc]
	day_time_left = DAY_LENGTH

	day_served = 0
	day_left = 0
	day_best_combo = 0
	day_gold_start = gold
	combo = 0

	day_break_panel.visible = false
	end_day_panel.visible = false
	upgrades_panel.visible = false  # апгрейды только в перерыв

	_apply_tables()        # включит нужное кол-во столов
	for a in craft_areas:  # очистим столы на старт дня (простое правило v1)
		a.clear_silent()

	# перезапускаем очередь на новый день (важно!)
	customer_queue.setup(
		Callable(progression, "pick_order_id"),
		Callable(self, "_pick_archetype"),
		Callable(self, "_serve_patience_max_for_day"),
		QUEUE_SIZE, APPROACH_TIME, ANNOUNCE_TIME, QUEUE_DRAIN_MULT
	)

	status_label.text = "Day started!"

func _end_day() -> void:
	if phase != GamePhase.DAY_ACTIVE:
		return

	phase = GamePhase.DAY_END

	# закрываем лавку
	for a in craft_areas:
		a.set_enabled(false) # очистит столы, и дроп не пройдет

	end_day_panel.visible = true
	day_break_panel.visible = false

	var profit := gold - day_gold_start
	end_summary_label.text = "Day %d results:\nServed: %d\nLeft: %d\nBest combo: %d\nProfit: %d" % [
		day_index, day_served, day_left, day_best_combo, profit
	]

	status_label.text = "Day ended!"

func _go_to_break() -> void:
	phase = GamePhase.DAY_BREAK
	day_break_panel.visible = true
	end_day_panel.visible = false
	status_label.text = "Break"

	# Ночная поставка — только если хотя бы один день уже был сыгран
	# (чтобы при запуске игры не “поставляло” поверх стартовых запасов)
	if day_index > 0:
		_apply_night_supply()

	# в перерыве можно открыть апгрейды
	_apply_tables()

func _night_supply_amount() -> int:
	var base := 2 + upgrades.replenish_level
	var mult := day_mod.night_supply_mult if day_mod != null else 1.0
	return max(0, int(round(float(base) * mult)))

func _apply_night_supply() -> void:
	var amount := _night_supply_amount()
	DataManager.replenish_tick(amount)
	status_label.text = "Night supply: +%d each" % amount
	_update_shelf_badges()

func _update_need_label() -> void:
	if not customer_queue.is_order_visible():
		need_label.text = "Need: (hidden)"
		return

	var active := customer_queue.get_active()
	if active == null:
		need_label.text = "Need: ?"
		return

	var r := DataManager.get_recipe(active.order_id)
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
	if not customer_queue.is_order_visible():
		return

	var active := customer_queue.get_active()
	if active == null:
		return

	var order_id := active.order_id

	for area in craft_areas:
		if area.has_item(order_id):
			area.remove_one(order_id, false)

			var result := DataManager.get_item(order_id)
			var base_gold := result.cost if result else 0
			var pay_mult := HeroArchetypes.pay_mult(active.archetype)
			
			var tip := 0
			if active.serve_time <= FAST_TIME:
				var chance := HeroArchetypes.tip_chance(active.archetype)
				if randf() < chance:
					tip = int(round(float(base_gold) * HeroArchetypes.tip_mult(active.archetype)))
			
			if active.serve_time <= FAST_TIME:
				combo += 1
			else:
				combo = 0

			var bonus_mult := 1.0 + float(combo) * 0.05
			var deal_mult := bargain_discount_mult if bargain_active else 1.0
			var total := int(round(float(base_gold) * pay_mult * combo_mult * deal_mult * _day_pay_mult())) + tip
			gold += total

			progression.on_delivered()
			status_label.text = "Delivered!"
			bargain_active = false
			bargain_discount_mult = 1.0
			bargain_row.visible = false
			day_served += 1
			day_best_combo = max(day_best_combo, combo)
			customer_queue.complete_active_order()
			call_deferred("_try_deliver_current_order")
			return


func _pick_archetype() -> int:
	if day_mod == null:
		return HeroArchetypes.pick()
	return DayModifier.pick_archetype(day_mod)

func _start_bargain_if_needed() -> void:
	bargain_active = false
	bargain_discount_mult = 1.0
	bargain_patience_bonus = 0.0
	bargain_row.visible = false

	var a := customer_queue.get_active()
	if a == null:
		return

	# только для торгаша
	if a.archetype != HeroArchetypes.Type.HAGGLER:
		return

	# шанс торга (можно 100% для теста)
	if randf() > 0.7:
		return

	bargain_active = true
	bargain_discount_mult = 0.85   # -15% золота
	bargain_patience_bonus = 0.25  # +25% к максимуму терпения (или к текущему)

	bargain_label.text = "Deal? -15% gold, +25% patience"
	bargain_row.visible = true

func _accept_bargain() -> void:
	if not bargain_active:
		return

	var a := customer_queue.get_active()
	if a != null and customer_queue.is_order_visible():
		# увеличим текущую и максимальную "служебную" терпеливость
		var add := a.serve_patience_max * bargain_patience_bonus
		a.serve_patience_max += add
		a.serve_patience += add

	status_label.text = "Deal."
	bargain_row.visible = false
	# bargain_active оставляем true, чтобы скидка применялась при оплате

func _reject_bargain() -> void:
	if not bargain_active:
		return

	status_label.text = "No deal."
	bargain_active = false
	bargain_discount_mult = 1.0
	bargain_row.visible = false

# ---------- UI / stock ----------

func _update_ui() -> void:
	day_label.text = "Day: %d" % day_index

	var day_left = max(0.0, day_time_left)
	var sec := int(day_left) % 60
	var min := int(day_left) / 60
	day_timer_label.text = "%02d:%02d" % [min, sec]

	gold_label.text = "Gold: %d" % gold
	combo_label.text = "Combo: %d" % combo
	level_label.text = "Level: %d" % progression.shop_level

	var active := customer_queue.get_active()
	if active == null:
		order_label.text = "Order: -"
		patience_bar.value = 0
		mood_label.text = "-"
	else:
		if not customer_queue.is_order_visible():
			order_label.text = "Order: (hidden)"
			patience_bar.value = 100
			mood_label.text = "..."
		else:
			var it := DataManager.get_item(active.order_id)
			order_label.text = "Order: " + (_safe_name(it) if it else String(active.order_id))

			var patience_ratio = clamp(active.serve_patience / active.serve_patience_max, 0.0, 1.0)
			patience_bar.value = patience_ratio * 100.0
			mood_label.text = "OK" if patience_ratio > MOOD_OK else ("WARN" if patience_ratio > MOOD_WARN else "ANGRY")

	# очередь
	var q: Array[String] = []
	for c in customer_queue.get_queue():
		var queue_ratio = clamp(c.queue_patience / c.queue_patience_max, 0.0, 1.0)
		q.append(str(int(round(queue_ratio * 100.0))) + "%")
	queue_label.text = "Queue: " + ", ".join(q)


func _safe_name(it: ItemDef) -> String:
	if it == null:
		return "?"
	var key := String(it.name_key)
	var s := tr(key)
	return s if s != key else String(it.id)


func _on_restock_pressed() -> void:
	if phase != GamePhase.DAY_BREAK:
			status_label.text = "Upgrades only in break"
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


func _on_replenish() -> void:
	DataManager.replenish_tick(upgrades.replenish_amount())
	replenish_timer.wait_time = upgrades.replenish_period()
	_update_shelf_badges()


func _update_shelf_badges() -> void:
	for shelf in shelf_items:
		if shelf != null:
			if shelf.has_method("refresh"):
				shelf.refresh()
			else:
				shelf._apply_view()


# ---------- upgrades ----------

func _apply_tables() -> void:
	var n := upgrades.active_table_count(craft_areas.size())
	for i in range(craft_areas.size()):
		craft_areas[i].set_enabled(i < n)

func _buy_more_tables() -> void:
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

func _buy_more_stock() -> void:
	var cost := upgrades.cost_more_stock()
	if gold < cost:
		status_label.text = "Not enough gold!"
		return

	gold -= cost
	upgrades.inc_stock()
	DataManager.add_stock_capacity_bonus(10)
	_refresh_upgrades_ui()
	_update_shelf_badges()

func _buy_replenish() -> void:
	var cost := upgrades.cost_replenish()
	if gold < cost:
		status_label.text = "Not enough gold!"
		return

	gold -= cost
	upgrades.inc_replenish()
	replenish_timer.wait_time = upgrades.replenish_period()
	_refresh_upgrades_ui()

func _buy_more_patience() -> void:
	var cost := upgrades.cost_more_patience()
	if gold < cost:
		status_label.text = "Not enough gold!"
		return

	gold -= cost
	upgrades.inc_patience()
	_refresh_upgrades_ui()

func _day_patience_mult() -> float:
	return day_mod.patience_mult if day_mod != null else 1.0

func _day_pay_mult() -> float:
	return day_mod.pay_mult if day_mod != null else 1.0

func _day_queue_drain_mult() -> float:
	return day_mod.queue_drain_mult if day_mod != null else 1.0

func _serve_patience_max_for_day() -> float:
	return upgrades.serve_patience_max() * _day_patience_mult()

func _refresh_upgrades_ui() -> void:
	btn_more_tables.text = "More tables (%d/%d) - %dg" % [
		upgrades.active_table_count(craft_areas.size()),
		craft_areas.size(),
		upgrades.cost_more_tables()
	]
	btn_more_stock.text = "Bigger stock (lvl %d) - %dg" % [upgrades.stock_level, upgrades.cost_more_stock()]
	btn_replenish.text = "Faster replenish (lvl %d) - %dg" % [upgrades.replenish_level, upgrades.cost_replenish()]
	btn_more_patience.text = "More patience (lvl %d) - %dg" % [upgrades.patience_level, upgrades.cost_more_patience()]
