class_name DayModifier
extends RefCounted

var id: StringName
var title: String
var desc: String

var patience_mult: float = 1.0
var pay_mult: float = 1.0
var queue_drain_mult: float = 1.0
var night_supply_mult: float = 1.0

# веса архетипов (сумма не обязана быть 100)
var w_normal: int = 45
var w_haggler: int = 20
var w_rusher: int = 20
var w_generous: int = 15

static func list() -> Array[DayModifier]:
	var a: Array[DayModifier] = []

	# 1) Rush Hour
	var m := DayModifier.new()
	m.id = &"rush_hour"
	m.title = "Rush Hour"
	m.desc = "-15% patience, +10% pay, queue faster"
	m.patience_mult = 0.85
	m.pay_mult = 1.10
	m.queue_drain_mult = 1.25
	m.w_rusher += 20
	a.append(m)

	# 2) Bargain Day
	m = DayModifier.new()
	m.id = &"bargain_day"
	m.title = "Bargain Day"
	m.desc = "More hagglers, slightly lower pay"
	m.pay_mult = 0.95
	m.w_haggler += 30
	a.append(m)

	# 3) Quiet Day
	m = DayModifier.new()
	m.id = &"quiet_day"
	m.title = "Quiet Day"
	m.desc = "+15% patience, queue slower"
	m.patience_mult = 1.15
	m.queue_drain_mult = 0.80
	m.pay_mult = 0.95
	a.append(m)

	# 4) Supply Issues (влияет на ночную поставку)
	m = DayModifier.new()
	m.id = &"supply_issues"
	m.title = "Supply Issues"
	m.desc = "Night supply reduced"
	m.night_supply_mult = 0.6
	m.pay_mult = 1.05
	a.append(m)

	# 5) Festival
	m = DayModifier.new()
	m.id = &"festival"
	m.title = "Festival"
	m.desc = "More generous heroes"
	m.w_generous += 30
	a.append(m)

	return a

static func pick() -> DayModifier:
	var l := list()
	return l[randi() % l.size()]

static func pick_archetype(mod: DayModifier) -> int:
	# Weighted random: NORMAL/HAGGLER/RUSHER/GENEROUS
	var total := mod.w_normal + mod.w_haggler + mod.w_rusher + mod.w_generous
	var roll = randi() % max(total, 1)

	if roll < mod.w_haggler:
		return HeroArchetypes.Type.HAGGLER
	roll -= mod.w_haggler

	if roll < mod.w_rusher:
		return HeroArchetypes.Type.RUSHER
	roll -= mod.w_rusher

	if roll < mod.w_generous:
		return HeroArchetypes.Type.GENEROUS

	return HeroArchetypes.Type.NORMAL
