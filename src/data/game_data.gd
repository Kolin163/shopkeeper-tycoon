class_name GameData
extends Resource

@export var items: Array[ItemDef] = []
@export var recipes: Array[RecipeDef] = []

func index_items() -> Dictionary:
	var d := {}
	for it in items:
		if it != null:
			d[it.id] = it
	return d
