class_name RecipeDef
extends Resource

@export var result: ItemDef
@export var components: Array[ItemDef] = []

# Для Power Treads и подобных: "один из вариантов"
@export var variant_options: Array[ItemDef] = []  # пусто => нет варианта
@export var requires_variant: bool = false        # true => надо выбрать 1 из variant_options
