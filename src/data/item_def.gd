class_name ItemDef
extends Resource

@export var id: StringName
@export var name_key: StringName # пример: &"item.power_treads"
@export var type: StringName = &"base" # base / upgrade / recipe_scroll
@export var cost: int = 0
@export var icon: Texture2D
@export var stock_max: int = 0  # 0 = бесконечно / upgrade. >0 = базовый с запасом
