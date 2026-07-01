extends PanelContainer
class_name Tile

var value := 2
var _label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	set_value(value)


func set_value(next_value: int) -> void:
	value = next_value

	var style := StyleBoxFlat.new()
	style.bg_color = _tile_color_for_value(value)
	style.border_color = Color(1.0, 1.0, 1.0, 0.12)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	add_theme_stylebox_override("panel", style)

	if _label != null:
		_label.text = str(value)
		_label.add_theme_font_size_override("font_size", _font_size_for_value(value))
		_label.add_theme_color_override("font_color", _text_color_for_value(value))


func pop() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.86, 0.86)
	modulate = Color.WHITE

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.16)


func spawn() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.62, 0.62)
	modulate = Color(1.0, 1.0, 1.0, 0.0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.22)
	tween.tween_property(self, "modulate:a", 1.0, 0.18)


func _font_size_for_value(tile_value: int) -> int:
	if tile_value >= 1000:
		return 24
	if tile_value >= 100:
		return 28
	return 34


func _text_color_for_value(tile_value: int) -> Color:
	if tile_value <= 4:
		return Color("#23303c")
	return Color("#f8f3e7")


func _tile_color_for_value(tile_value: int) -> Color:
	match tile_value:
		2:
			return Color("#f1dfbf")
		4:
			return Color("#ead08e")
		8:
			return Color("#e59f55")
		16:
			return Color("#df6b54")
		32:
			return Color("#c94d6c")
		64:
			return Color("#8d5fd3")
		128:
			return Color("#4b7bd8")
		256:
			return Color("#3aa6a1")
		_:
			return Color("#2e7d58")
