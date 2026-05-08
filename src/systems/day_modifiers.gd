class_name DayModifiers
extends RefCounted

static var _cache: Array[DayModifier] = []

static func list() -> Array[DayModifier]:
	if not _cache.is_empty():
		return _cache

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

	# 4) Supply Issues
	m = DayModifier.new()
	m.id = &"supply_issues"
	m.title = "Supply Issues"
	m.desc = "Night supply reduced"
	m.night_supply_mult = 0.60
	m.pay_mult = 1.05
	a.append(m)

	# 5) Festival
	m = DayModifier.new()
	m.id = &"festival"
	m.title = "Festival"
	m.desc = "More generous heroes"
	m.w_generous += 30
	a.append(m)

	_cache = a
	return _cache

static func pick() -> DayModifier:
	var l := list()
	if l.is_empty():
		return DayModifier.new()
	return l[randi() % l.size()]

static func pick_archetype(mod: DayModifier) -> int:
	var w_h = max(0, mod.w_haggler)
	var w_r = max(0, mod.w_rusher)
	var w_g = max(0, mod.w_generous)
	var w_n = max(0, mod.w_normal)

	var total = w_n + w_h + w_r + w_g
	if total <= 0:
		return HeroArchetypes.Type.NORMAL

	var roll = randi() % total

	if roll < w_h:
		return HeroArchetypes.Type.HAGGLER
	roll -= w_h

	if roll < w_r:
		return HeroArchetypes.Type.RUSHER
	roll -= w_r

	if roll < w_g:
		return HeroArchetypes.Type.GENEROUS

	return HeroArchetypes.Type.NORMAL
