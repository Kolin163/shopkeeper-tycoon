extends Control
class_name ShelfItem

@export var item: ItemDef
enum HintState { NONE, REQUIRED, VARIANT }

var hint_state: int = HintState.NONE
@onready var hint_overlay: ColorRect = $HintOverlay
@onready var bg: ColorRect = $Bg
@onready var icon: TextureRect = $Icon
@onready var name_label: Label = $NameLabel
@onready var count_label: Label = $CountLabel

func _ready() -> void:
	_apply_view()

func refresh() -> void:
	_apply_view()
	_update_hint_overlay()

func set_hint_state(state: int) -> void:
	hint_state = state
	_update_hint_overlay()

func _apply_view() -> void:
	if item == null:
		bg.color = Color(0.2, 0.2, 0.2, 1.0)
		icon.visible = false
		name_label.visible = true
		name_label.text = "NULL"
		count_label.visible = false
		modulate = Color.WHITE
		return

	var display := _display_name()
	tooltip_text = display

	# иконка или плейсхолдер
	if item.icon != null:
		bg.color = Color(0.08, 0.08, 0.08, 1.0)
		icon.texture = item.icon
		icon.visible = true
		name_label.visible = false
	else:
		bg.color = _color_from_id(String(item.id))
		icon.visible = false
		name_label.visible = true
		name_label.text = display

	# склад
	if not DataManager.is_stocked(item.id):
		# не складской (upgrade/recipe_scroll и т.п.)
		count_label.visible = false
		modulate = Color.WHITE
		return

	var cnt := DataManager.get_stock(item.id)
	count_label.visible = true
	count_label.text = str(cnt)

	modulate = Color(0.4, 0.4, 0.4, 1.0) if cnt <= 0 else Color.WHITE

func _update_hint_overlay() -> void:
	if hint_overlay == null:
		return

	match hint_state:
		HintState.NONE:
			hint_overlay.visible = false
		HintState.REQUIRED:
			hint_overlay.visible = true
			hint_overlay.color = Color(0.2, 1.0, 0.2, 0.20) # зелёный
		HintState.VARIANT:
			hint_overlay.visible = true
			hint_overlay.color = Color(0.2, 0.6, 1.0, 0.20) # синий

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null

	# единое правило: если stock закончился — нельзя тащить.
	# для нескладских has_stock() вернёт true, и drag будет разрешён.
	if not DataManager.has_stock(item.id):
		return null

	set_drag_preview(_make_drag_preview())
	return item

func _display_name() -> String:
	var key := String(item.name_key)
	var s := tr(key)
	return s if s != key else String(item.id)

func _color_from_id(s: String) -> Color:
	var h := float(abs(s.hash() % 360)) / 360.0
	return Color.from_hsv(h, 0.35, 0.85, 1.0)

func _make_drag_preview() -> Control:
	var p := Control.new()
	p.custom_minimum_size = Vector2(48, 48)

	var bgp := ColorRect.new()
	bgp.anchor_right = 1
	bgp.anchor_bottom = 1
	bgp.color = bg.color
	p.add_child(bgp)

	if item.icon != null:
		var ic := TextureRect.new()
		ic.anchor_right = 1
		ic.anchor_bottom = 1
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture = item.icon
		p.add_child(ic)
	else:
		var l := Label.new()
		l.anchor_right = 1
		l.anchor_bottom = 1
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.text = _display_name()
		p.add_child(l)

	return p
