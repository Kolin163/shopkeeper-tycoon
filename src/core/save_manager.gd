class_name SaveManager
extends RefCounted

const DEV_PATH := "res://_dev_save.json"
const PROD_PATH := "user://save.json"

static func _path() -> String:
	# В Web нельзя писать в res://, в экспортах тоже почти всегда нельзя.
	# Поэтому res:// используем ТОЛЬКО в редакторе (для удобства).
	if OS.has_feature("editor") and not OS.has_feature("web"):
		return DEV_PATH
	return PROD_PATH

static func load_dict() -> Dictionary:
	var path := _path()
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()

	var v = JSON.parse_string(text)
	return v if typeof(v) == TYPE_DICTIONARY else {}

static func save_dict(data: Dictionary) -> void:
	var path := _path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
