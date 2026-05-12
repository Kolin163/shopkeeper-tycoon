extends PanelContainer
class_name LogUI

@export var max_lines: int = 6
@export var default_ttl: float = 3.0

@onready var lines: VBoxContainer = %Lines

var _entries: Array[Dictionary] = [] # { "label": Label, "ttl": float }

func push(text: String, ttl: float = -1.0) -> void:
	if ttl < 0.0:
		ttl = default_ttl

	# создаём строку
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(1, 1, 1, 1)
	lines.add_child(l)

	_entries.append({ "label": l, "ttl": ttl })

	# ограничение по количеству
	while _entries.size() > max_lines:
		var e = _entries.pop_front()
		var lab: Label = e["label"]
		if is_instance_valid(lab):
			lab.queue_free()

func clear() -> void:
	for e in _entries:
		var lab: Label = e["label"]
		if is_instance_valid(lab):
			lab.queue_free()
	_entries.clear()

func _process(delta: float) -> void:
	# убывание ttl + плавное исчезновение
	for i in range(_entries.size() - 1, -1, -1):
		var e := _entries[i]
		e["ttl"] = float(e["ttl"]) - delta
		var lab: Label = e["label"]

		if not is_instance_valid(lab):
			_entries.remove_at(i)
			continue

		# fade последние 0.6 сек
		var t := float(e["ttl"])
		if t < 0.6:
			lab.modulate.a = clamp(t / 0.6, 0.0, 1.0)

		if t <= 0.0:
			lab.queue_free()
			_entries.remove_at(i)
