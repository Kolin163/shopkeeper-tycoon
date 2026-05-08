@tool
extends Node
class_name DataValidationRunner

@export var items_dir: String = "res://data/items"
@export var recipes_dir: String = "res://data/recipes"

@export var write_report_to_file: bool = true
@export var report_path_editor: String = "res://_validation_report.txt"
@export var report_path_fallback: String = "user://validation_report.txt"

@export var run_now: bool = false:
	set(v):
		run_now = false
		if v:
			last_report = validate()
			if write_report_to_file:
				_write_report(last_report)

@export_multiline var last_report: String = ""

const VALID_TYPES := [&"base", &"upgrade", &"recipe_scroll"]

func validate() -> String:
	var items := _load_resources_recursive(items_dir, "ItemDef")
	var recipes := _load_resources_recursive(recipes_dir, "RecipeDef")

	var items_by_id: Dictionary = {} # StringName -> ItemDef
	var errors: Array[String] = []
	var warnings: Array[String] = []

	# ---- items ----
	for it in items:
		var item := it as ItemDef
		if item == null:
			continue
		if item.id == StringName():
			errors.append("ItemDef with empty id: " + _res_path(item))
			continue

		if items_by_id.has(item.id):
			errors.append("Duplicate item id: %s (%s and %s)" % [
				String(item.id), _res_path(items_by_id[item.id]), _res_path(item)
			])
		else:
			items_by_id[item.id] = item

		if item.name_key == StringName():
			warnings.append("Item '%s' has empty name_key (%s)" % [String(item.id), _res_path(item)])

		if not VALID_TYPES.has(item.type):
			warnings.append("Item '%s' has unknown type '%s' (%s)" % [String(item.id), String(item.type), _res_path(item)])

		if item.tier < 1:
			warnings.append("Item '%s' tier < 1 (%s)" % [String(item.id), _res_path(item)])

		if item.cost < 0:
			errors.append("Item '%s' cost < 0 (%s)" % [String(item.id), _res_path(item)])

	# ---- recipes ----
	var recipes_by_result: Dictionary = {} # StringName -> RecipeDef

	for rr in recipes:
		var r := rr as RecipeDef
		if r == null:
			continue

		if r.result == null or r.result.id == StringName():
			errors.append("RecipeDef with missing result (%s)" % _res_path(r))
			continue

		if recipes_by_result.has(r.result.id):
			warnings.append("Duplicate recipe for result '%s' (%s and %s)" % [
				String(r.result.id), _res_path(recipes_by_result[r.result.id]), _res_path(r)
			])
		recipes_by_result[r.result.id] = r

		if r.requires_variant and r.variant_options.is_empty():
			errors.append("Recipe '%s' requires_variant=true but variant_options empty (%s)" % [String(r.result.id), _res_path(r)])

		if (not r.requires_variant) and (not r.variant_options.is_empty()):
			warnings.append("Recipe '%s' has variant_options but requires_variant=false (%s)" % [String(r.result.id), _res_path(r)])

		for c in r.components:
			if c == null or c.id == StringName():
				errors.append("Recipe '%s' has null/empty-id component (%s)" % [String(r.result.id), _res_path(r)])
				break

		for opt in r.variant_options:
			if opt == null or opt.id == StringName():
				errors.append("Recipe '%s' has null/empty-id variant option (%s)" % [String(r.result.id), _res_path(r)])
				break

	# ---- sanity: upgrade items without recipe ----
	for id in items_by_id.keys():
		var item: ItemDef = items_by_id[id]
		if item.type == &"upgrade" and not recipes_by_result.has(id):
			warnings.append("Upgrade item '%s' has no recipe (%s)" % [String(id), _res_path(item)])

	# ---- cycle detection ----
	var state: Dictionary = {} # StringName -> int (0=unseen,1=visiting,2=done)

	for id in recipes_by_result.keys():
		if int(state.get(id, 0)) == 0:
			_dfs_cycle(id, recipes_by_result, state, [], errors)

	# ---- report ----
	var header := []
	header.append("VALIDATION REPORT")
	header.append("Items loaded: %d" % items.size())
	header.append("Recipes loaded: %d" % recipes.size())
	header.append("Unique item ids: %d" % items_by_id.size())
	header.append("Recipes by result: %d" % recipes_by_result.size())
	header.append("Errors: %d" % errors.size())
	header.append("Warnings: %d" % warnings.size())
	header.append("")

	var out := []
	out.append("\n".join(header))

	if not errors.is_empty():
		out.append("ERRORS:")
		for i in range(errors.size()):
			out.append("%d) %s" % [i + 1, errors[i]])
		out.append("")

	if not warnings.is_empty():
		out.append("WARNINGS:")
		for i in range(warnings.size()):
			out.append("%d) %s" % [i + 1, warnings[i]])
		out.append("")

	if errors.is_empty() and warnings.is_empty():
		out.append("OK: no issues found.")

	return "\n".join(out)

func _dfs_cycle(id: StringName, recipes_by_result: Dictionary, state: Dictionary, stack: Array[StringName], errors: Array[String]) -> void:
	state[id] = 1
	stack.append(id)

	var r: RecipeDef = recipes_by_result.get(id, null)
	if r != null:
		for c in r.components:
			if c == null:
				continue
			var next_id := c.id
			if recipes_by_result.has(next_id):
				var st := int(state.get(next_id, 0))
				if st == 0:
					_dfs_cycle(next_id, recipes_by_result, state, stack, errors)
				elif st == 1:
					# found cycle
					var cycle := []
					var start := stack.find(next_id)
					if start >= 0:
						for j in range(start, stack.size()):
							cycle.append(String(stack[j]))
						cycle.append(String(next_id))
					else:
						cycle = [String(next_id), String(id), String(next_id)]
					errors.append("Cycle detected: " + " -> ".join(cycle))

	state[id] = 2
	stack.pop_back()

func _load_resources_recursive(dir_path: String, expected_class: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var entries: PackedStringArray = ResourceLoader.list_directory(dir_path)
	entries.sort()

	for name in entries:
		if name.ends_with("/"):
			out.append_array(_load_resources_recursive(dir_path + "/" + name.trim_suffix("/"), expected_class))
			continue

		var ext := name.get_extension().to_lower()
		if ext != "tres" and ext != "res":
			continue

		var path := dir_path + "/" + name
		var res := ResourceLoader.load(path)
		if res == null:
			continue
		# мягкая фильтрация по классу
		if expected_class != "" and not res.is_class(expected_class):
			continue
		out.append(res)

	return out

func _write_report(text: String) -> void:
	var path := report_path_fallback
	if OS.has_feature("editor") and not OS.has_feature("web"):
		path = report_path_editor

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()

func _res_path(res: Resource) -> String:
	var p := res.resource_path
	return p if not p.is_empty() else "<no_path>"
