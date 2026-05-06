class_name Upgrades
extends RefCounted

signal changed

var tables_level: int = 0
var stock_level: int = 0
var replenish_level: int = 0
var patience_level: int = 0

func active_table_count(total_tables: int) -> int:
	return clamp(1 + tables_level, 1, total_tables)

func replenish_period() -> float:
	return max(1.5, 5.0 - float(replenish_level) * 0.5)

func replenish_amount() -> int:
	return 1 + replenish_level

func serve_patience_max() -> float:
	return 12.0 + float(patience_level) * 2.0

func cost_more_tables() -> int:
	return 300 + tables_level * 400

func cost_more_stock() -> int:
	return 200 + stock_level * 250

func cost_replenish() -> int:
	return 250 + replenish_level * 300

func cost_more_patience() -> int:
	return 200 + patience_level * 250

func inc_tables() -> void:
	tables_level += 1
	changed.emit()

func inc_stock() -> void:
	stock_level += 1
	changed.emit()

func inc_replenish() -> void:
	replenish_level += 1
	changed.emit()

func inc_patience() -> void:
	patience_level += 1
	changed.emit()
