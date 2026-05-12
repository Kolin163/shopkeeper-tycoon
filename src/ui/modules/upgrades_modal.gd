extends Control
class_name UpgradesModal

signal close_pressed
signal buy_tables
signal buy_stock
signal buy_replenish
signal buy_patience

@onready var btn_more_tables: Button = %BtnMoreTables
@onready var btn_more_stock: Button = %BtnMoreStock
@onready var btn_replenish: Button = %BtnReplenish
@onready var btn_more_patience: Button = %BtnMorePatience
@onready var btn_close: Button = %BtnCloseUpgrades

func _ready() -> void:
	btn_close.pressed.connect(func(): close_pressed.emit())
	btn_more_tables.pressed.connect(func(): buy_tables.emit())
	btn_more_stock.pressed.connect(func(): buy_stock.emit())
	btn_replenish.pressed.connect(func(): buy_replenish.emit())
	btn_more_patience.pressed.connect(func(): buy_patience.emit())

func set_texts(tables: String, stock: String, repl: String, pat: String) -> void:
	btn_more_tables.text = tables
	btn_more_stock.text = stock
	btn_replenish.text = repl
	btn_more_patience.text = pat
