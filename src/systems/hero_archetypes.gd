class_name HeroArchetypes
extends RefCounted

enum Type { NORMAL, HAGGLER, RUSHER, GENEROUS }

static func pick() -> int:
	var roll := randi() % 100
	if roll < 20:  return Type.HAGGLER
	if roll < 40:  return Type.RUSHER
	if roll < 55:  return Type.GENEROUS
	return Type.NORMAL

static func name_key(t: int) -> StringName:
	match t:
		Type.HAGGLER:  return &"hero.haggler"
		Type.RUSHER:   return &"hero.rusher"
		Type.GENEROUS: return &"hero.generous"
		_:             return &"hero.normal"

static func patience_mult(t: int) -> float:
	match t:
		Type.RUSHER:   return 0.85   # меньше терпения
		Type.HAGGLER:  return 1.15   # чуть больше терпения
		_:             return 1.0

static func pay_mult(t: int) -> float:
	match t:
		Type.HAGGLER:  return 0.85   # платит меньше
		Type.RUSHER:   return 1.10   # платит больше
		_:             return 1.0

static func tip_chance(t: int) -> float:
	match t:
		Type.GENEROUS: return 0.35
		_:             return 0.0

static func tip_mult(t: int) -> float:
	match t:
		Type.GENEROUS: return 0.25   # +25% чаевых от base
		_:             return 0.0

static func say_order(t: int) -> String:
	match t:
		Type.HAGGLER:  return "…Сделай скидку и я доволен."
		Type.RUSHER:   return "Быстро! У меня файт!"
		Type.GENEROUS: return "Если успеешь — будут чаевые."
		_:             return "Мне нужен артефакт."

static func order_line_key(t: int) -> StringName:
	match t:
		Type.HAGGLER:  return &"line.haggler_order"
		Type.RUSHER:   return &"line.rusher_order"
		Type.GENEROUS: return &"line.generous_order"
		_:             return &"line.normal_order"
