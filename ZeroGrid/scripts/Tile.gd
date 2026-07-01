extends Control
class_name Tile

var value := 2
var pressure := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_value(value)


func _draw() -> void:
	var center := size * 0.5
	var radius: float = min(size.x, size.y) * _radius_scale_for_value(value)

	if value >= 32:
		_draw_burst(center, radius)
		return

	var colors := _bubble_colors_for_value(value)
	var base: Color = colors["base"]
	var rim: Color = colors["rim"]
	var glow: Color = colors["glow"]
	var shadow: Color = colors["shadow"]

	draw_circle(center + Vector2(radius * 0.1, radius * 0.16), radius * 0.95, Color(0.0, 0.0, 0.0, 0.12))
	draw_circle(center, radius, glow)
	draw_circle(center, radius * 0.88, base)
	draw_circle(center + Vector2(-radius * 0.22, -radius * 0.24), radius * 0.34, Color(1.0, 1.0, 1.0, 0.22))
	draw_circle(center + Vector2(-radius * 0.32, -radius * 0.34), radius * 0.13, Color(1.0, 1.0, 1.0, 0.7))
	draw_arc(center, radius * 0.93, -0.82, 1.35, 48, rim, max(2.0, radius * 0.075), true)
	draw_arc(center, radius * 0.64, 1.1, 2.58, 28, Color(1.0, 1.0, 1.0, 0.17), max(1.0, radius * 0.032), true)
	draw_arc(center + Vector2(radius * 0.08, radius * 0.08), radius * 0.53, 3.7, 5.1, 26, shadow, max(1.0, radius * 0.036), true)

	_draw_stage_marks(center, radius)

	if value >= 8:
		draw_arc(center, radius * 1.06, 0.18, 5.9, 56, Color(1.0, 1.0, 1.0, 0.18), max(1.0, radius * 0.028), true)

	if value >= 16:
		_draw_pressure_cracks(center, radius)


func set_value(next_value: int) -> void:
	value = next_value
	pressure = clamp(float(value) / 32.0, 0.0, 1.0)
	queue_redraw()


func pop() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.86, 0.86)
	modulate = Color.WHITE

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.18)


func spawn() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.62, 0.62)
	modulate = Color(1.0, 1.0, 1.0, 0.0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.24)
	tween.tween_property(self, "modulate:a", 1.0, 0.18)


func _radius_scale_for_value(tile_value: int) -> float:
	match tile_value:
		2:
			return 0.32
		4:
			return 0.35
		8:
			return 0.38
		16:
			return 0.42
		_:
			return 0.43


func _bubble_colors_for_value(tile_value: int) -> Dictionary:
	match tile_value:
		2:
			return {
				"base": Color("#7fd7ff"),
				"rim": Color("#d7f5ff"),
				"glow": Color("#2b85c6"),
				"shadow": Color("#236b9d"),
			}
		4:
			return {
				"base": Color("#74f0c7"),
				"rim": Color("#d7fff1"),
				"glow": Color("#238e78"),
				"shadow": Color("#1b6c62"),
			}
		8:
			return {
				"base": Color("#ffd36e"),
				"rim": Color("#fff0bd"),
				"glow": Color("#d07b26"),
				"shadow": Color("#9b5124"),
			}
		16:
			return {
				"base": Color("#ff6b83"),
				"rim": Color("#ffd1d9"),
				"glow": Color("#c92f5f"),
				"shadow": Color("#872041"),
			}
		_:
			return {
				"base": Color("#ffed9a"),
				"rim": Color("#ffffff"),
				"glow": Color("#ff5a43"),
				"shadow": Color("#af2632"),
			}


func _draw_stage_marks(center: Vector2, radius: float) -> void:
	var marks := clampi(int(log(float(value)) / log(2.0)) - 1, 1, 4)
	var start_x := center.x - float(marks - 1) * radius * 0.12
	var mark_y := center.y + radius * 0.46

	for i in range(marks):
		var mark_center := Vector2(start_x + float(i) * radius * 0.24, mark_y)
		draw_circle(mark_center, radius * 0.045, Color(1.0, 1.0, 1.0, 0.64))


func _draw_pressure_cracks(center: Vector2, radius: float) -> void:
	var crack_color := Color("#5c172e")
	crack_color.a = 0.72
	var crack_width: float = max(2.0, radius * 0.045)
	var paths := [
		[
			center + Vector2(radius * 0.08, -radius * 0.56),
			center + Vector2(radius * 0.02, -radius * 0.22),
			center + Vector2(radius * 0.19, radius * 0.02),
		],
		[
			center + Vector2(radius * 0.47, -radius * 0.12),
			center + Vector2(radius * 0.24, radius * 0.05),
			center + Vector2(radius * 0.34, radius * 0.34),
		],
		[
			center + Vector2(-radius * 0.14, radius * 0.52),
			center + Vector2(-radius * 0.04, radius * 0.24),
			center + Vector2(-radius * 0.28, radius * 0.06),
		],
	]

	for path in paths:
		for i in range(path.size() - 1):
			draw_line(path[i], path[i + 1], crack_color, crack_width, true)


func _draw_burst(center: Vector2, radius: float) -> void:
	var points: PackedVector2Array = []
	var steps := 18
	for i in range(steps):
		var angle := -PI * 0.5 + TAU * float(i) / float(steps)
		var spike_radius: float = radius * (1.22 if i % 2 == 0 else 0.62)
		points.append(center + Vector2(cos(angle), sin(angle)) * spike_radius)

	draw_polygon(points, PackedColorArray([Color("#ffed6a")]))
	points.append(points[0])
	draw_polyline(points, Color("#ff7447"), max(2.0, radius * 0.07), true)
	draw_circle(center, radius * 0.58, Color("#fff7c4"))
	draw_circle(center, radius * 0.28, Color("#ffffff"))
