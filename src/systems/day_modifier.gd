class_name DayModifier
extends RefCounted

var id: StringName = &""
var title_key: StringName = &""
var desc_key: StringName = &""
var title: String = ""
var desc: String = ""

# Gameplay multipliers
var patience_mult: float = 1.0       # multiplies serve_patience_max
var pay_mult: float = 1.0            # multiplies gold payout
var queue_drain_mult: float = 1.0    # multiplies queue drain speed
var night_supply_mult: float = 1.0   # multiplies night supply amount

# Archetype weights (sum can be anything)
var w_normal: int = 45
var w_haggler: int = 20
var w_rusher: int = 20
var w_generous: int = 15

var vip_pay_mult: float = 1.0
var vip_patience_mult: float = 1.0

func total_weight() -> int:
	return max(0, w_normal) + max(0, w_haggler) + max(0, w_rusher) + max(0, w_generous)
