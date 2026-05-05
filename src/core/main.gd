extends Node


func _ready() -> void:
	get_tree().change_scene_to_file("res://scenes/boot/boot.tscn")
	await  get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/shop/shop.tscn")
