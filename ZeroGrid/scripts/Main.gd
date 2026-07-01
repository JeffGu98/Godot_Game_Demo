extends Control

const TileScript := preload("res://scripts/Tile.gd")

const BOARD_SIZE := 6
const CLEAR_VALUE := 32
const START_TILES := 3
const BOARD_PADDING := 12.0
const TILE_GAP := 10.0
const MOVE_DURATION := 0.14
const MERGE_SETTLE_DURATION := 0.16
const CLEAR_DURATION := 0.22
const SPAWN_DURATION := 0.22

const DIR_LEFT := Vector2i(-1, 0)
const DIR_RIGHT := Vector2i(1, 0)
const DIR_UP := Vector2i(0, -1)
const DIR_DOWN := Vector2i(0, 1)
const NEIGHBORS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var rng := RandomNumberGenerator.new()
var board := []
var score := 0
var best_score := 0
var moves := 0
var combo := 0
var game_over := false
var is_animating := false
var cell_size := 64.0

var background: ColorRect
var title_label: Label
var rule_label: Label
var score_label: Label
var best_label: Label
var combo_label: Label
var status_label: Label
var board_panel: Panel
var cell_nodes: Array[Panel] = []
var tile_nodes := []
var tiles_by_pos := {}


func _ready() -> void:
	rng.randomize()
	_build_ui()
	_new_game()
	resized.connect(_layout)
	call_deferred("_layout")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if is_animating:
		return

	match key_event.keycode:
		KEY_LEFT, KEY_A:
			_try_move(DIR_LEFT)
		KEY_RIGHT, KEY_D:
			_try_move(DIR_RIGHT)
		KEY_UP, KEY_W:
			_try_move(DIR_UP)
		KEY_DOWN, KEY_S:
			_try_move(DIR_DOWN)
		KEY_R:
			_new_game()


func _build_ui() -> void:
	background = ColorRect.new()
	background.color = Color("#111923")
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	title_label = _make_label("归零格", 38, Color("#f7eddd"), HORIZONTAL_ALIGNMENT_LEFT)
	add_child(title_label)

	rule_label = _make_label("BUBBLE 32  /  POP", 16, Color("#b9c7d6"), HORIZONTAL_ALIGNMENT_LEFT)
	add_child(rule_label)

	score_label = _make_stat_label()
	add_child(score_label)

	best_label = _make_stat_label()
	add_child(best_label)

	combo_label = _make_stat_label()
	add_child(combo_label)

	board_panel = Panel.new()
	var board_style := StyleBoxFlat.new()
	board_style.bg_color = Color("#233142")
	board_style.border_color = Color("#34475d")
	board_style.border_width_left = 2
	board_style.border_width_top = 2
	board_style.border_width_right = 2
	board_style.border_width_bottom = 2
	board_style.corner_radius_top_left = 16
	board_style.corner_radius_top_right = 16
	board_style.corner_radius_bottom_left = 16
	board_style.corner_radius_bottom_right = 16
	board_panel.add_theme_stylebox_override("panel", board_style)
	add_child(board_panel)

	for i in range(BOARD_SIZE * BOARD_SIZE):
		var cell := Panel.new()
		var cell_style := StyleBoxFlat.new()
		cell_style.bg_color = Color("#182435")
		cell_style.border_color = Color(1.0, 1.0, 1.0, 0.05)
		cell_style.border_width_left = 1
		cell_style.border_width_top = 1
		cell_style.border_width_right = 1
		cell_style.border_width_bottom = 1
		cell_style.corner_radius_top_left = 8
		cell_style.corner_radius_top_right = 8
		cell_style.corner_radius_bottom_left = 8
		cell_style.corner_radius_bottom_right = 8
		cell.add_theme_stylebox_override("panel", cell_style)
		board_panel.add_child(cell)
		cell_nodes.append(cell)

	status_label = _make_label("", 20, Color("#f4d68c"), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(status_label)


func _make_label(text: String, font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_stat_label() -> Label:
	var label := _make_label("", 18, Color("#e7eef7"), HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_font_size_override("font_size", 18)
	return label


func _layout() -> void:
	if board_panel == null:
		return

	var viewport_size := get_viewport_rect().size
	var margin := 34.0
	var board_side: float = min(viewport_size.x - margin * 2.0, viewport_size.y - 172.0)
	board_side = clamp(board_side, 340.0, 540.0)

	title_label.position = Vector2(margin, 26.0)
	title_label.size = Vector2(280.0, 46.0)

	rule_label.position = Vector2(margin + 2.0, 72.0)
	rule_label.size = Vector2(260.0, 24.0)

	var stat_width := 110.0
	var stat_gap := 10.0
	var stat_top := 34.0
	combo_label.position = Vector2(viewport_size.x - margin - stat_width, stat_top)
	combo_label.size = Vector2(stat_width, 58.0)
	best_label.position = combo_label.position - Vector2(stat_width + stat_gap, 0.0)
	best_label.size = Vector2(stat_width, 58.0)
	score_label.position = best_label.position - Vector2(stat_width + stat_gap, 0.0)
	score_label.size = Vector2(stat_width, 58.0)

	board_panel.size = Vector2(board_side, board_side)
	board_panel.position = Vector2((viewport_size.x - board_side) * 0.5, 120.0)

	status_label.position = Vector2(margin, board_panel.position.y + board_side + 18.0)
	status_label.size = Vector2(viewport_size.x - margin * 2.0, 36.0)

	cell_size = (board_side - BOARD_PADDING * 2.0 - TILE_GAP * float(BOARD_SIZE - 1)) / float(BOARD_SIZE)
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var index := y * BOARD_SIZE + x
			var cell := cell_nodes[index]
			cell.position = _cell_position(Vector2i(x, y))
			cell.size = Vector2(cell_size, cell_size)

	for tile in tile_nodes:
		if is_instance_valid(tile):
			tile.size = Vector2(cell_size, cell_size)

	if not is_animating:
		for pos in tiles_by_pos.keys():
			var tile = tiles_by_pos[pos]
			if is_instance_valid(tile):
				tile.position = _cell_position(pos as Vector2i)


func _new_game() -> void:
	is_animating = false
	board = _empty_board()
	score = 0
	moves = 0
	combo = 0
	game_over = false
	status_label.text = "READY"

	var spawn_positions: Array[Vector2i] = []
	for i in range(START_TILES):
		var spawn_result := _spawn_random_tile()
		if spawn_result["spawned"]:
			spawn_positions.append(spawn_result["position"])

	_render_board(spawn_positions)
	_update_stats()


func _try_move(direction: Vector2i) -> void:
	if game_over or is_animating:
		return

	var result := _plan_slide(direction)
	if not result["changed"]:
		status_label.text = "NO MOVE"
		return

	is_animating = true
	status_label.text = "MOVE"

	await _animate_movements(result["motions"])

	board = result["board"]
	score += result["score_gain"]
	moves += 1

	_render_board([], result["merge_positions"])
	_update_stats()
	if not result["merge_positions"].is_empty():
		await get_tree().create_timer(MERGE_SETTLE_DURATION).timeout

	var cleared_positions := _resolve_clears()
	if cleared_positions.is_empty():
		combo = 0
	else:
		combo += 1
		score += cleared_positions.size() * 25 * combo
		_shake_board()
		_update_stats()
		_update_status(result["merges"], cleared_positions.size())
		await _animate_clears(cleared_positions)
		_render_board()

	var spawn_positions: Array[Vector2i] = []
	var spawn_result := _spawn_random_tile()
	if spawn_result["spawned"]:
		spawn_positions.append(spawn_result["position"])

	best_score = max(best_score, score)

	_render_board(spawn_positions)
	_update_stats()
	_update_status(result["merges"], cleared_positions.size())

	if not _has_any_move():
		game_over = true
		status_label.text = "GAME OVER  /  R"

	if not spawn_positions.is_empty():
		await get_tree().create_timer(SPAWN_DURATION).timeout

	is_animating = false


func _plan_slide(direction: Vector2i) -> Dictionary:
	var next_board := _empty_board()
	var motions := []
	var merge_positions: Array[Vector2i] = []
	var score_gain := 0
	var merge_count := 0

	for line_index in range(BOARD_SIZE):
		var coords := _line_coords(line_index, direction)
		var entries := []

		for pos in coords:
			var tile_value: int = board[pos.y][pos.x]
			if tile_value != 0:
				entries.append({
					"position": pos,
					"value": tile_value,
				})

		var output_index := 0
		var i := 0
		while i < entries.size():
			var first: Dictionary = entries[i]
			var target_pos: Vector2i = coords[output_index]

			if i + 1 < entries.size() and first["value"] == entries[i + 1]["value"]:
				var second: Dictionary = entries[i + 1]
				var merged_value: int = first["value"] * 2
				next_board[target_pos.y][target_pos.x] = merged_value
				motions.append({
					"from": first["position"],
					"to": target_pos,
					"merged": true,
				})
				motions.append({
					"from": second["position"],
					"to": target_pos,
					"merged": true,
				})
				merge_positions.append(target_pos)
				score_gain += merged_value
				merge_count += 1
				i += 2
			else:
				next_board[target_pos.y][target_pos.x] = first["value"]
				motions.append({
					"from": first["position"],
					"to": target_pos,
					"merged": false,
				})
				i += 1
			output_index += 1

	return {
		"board": next_board,
		"changed": not _boards_equal(board, next_board),
		"score_gain": score_gain,
		"merges": merge_count,
		"motions": motions,
		"merge_positions": merge_positions,
	}


func _line_coords(line_index: int, direction: Vector2i) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []

	if direction.x != 0:
		var y := line_index
		if direction.x < 0:
			for x in range(BOARD_SIZE):
				coords.append(Vector2i(x, y))
		else:
			for x in range(BOARD_SIZE - 1, -1, -1):
				coords.append(Vector2i(x, y))
	else:
		var x := line_index
		if direction.y < 0:
			for y in range(BOARD_SIZE):
				coords.append(Vector2i(x, y))
		else:
			for y in range(BOARD_SIZE - 1, -1, -1):
				coords.append(Vector2i(x, y))

	return coords


func _resolve_clears() -> Array[Vector2i]:
	var clear_map := {}

	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var tile_value: int = board[y][x]
			if tile_value < CLEAR_VALUE:
				continue

			var origin := Vector2i(x, y)
			clear_map[origin] = true
			for offset in NEIGHBORS:
				var neighbor: Vector2i = origin + offset
				if _inside_board(neighbor) and board[neighbor.y][neighbor.x] > 0 and board[neighbor.y][neighbor.x] <= tile_value / 2:
					clear_map[neighbor] = true

	var cleared: Array[Vector2i] = []
	for pos in clear_map.keys():
		var clear_pos := pos as Vector2i
		var cleared_value: int = board[clear_pos.y][clear_pos.x]
		if cleared_value == 0:
			continue
		score += cleared_value
		board[clear_pos.y][clear_pos.x] = 0
		cleared.append(clear_pos)

	return cleared


func _animate_movements(motions: Array) -> void:
	var tween: Tween = null
	var animated_count := 0

	for motion in motions:
		var from_pos: Vector2i = motion["from"]
		var to_pos: Vector2i = motion["to"]
		var tile = tiles_by_pos.get(from_pos)
		if not is_instance_valid(tile):
			continue

		if tween == null:
			tween = create_tween()
			tween.set_parallel(true)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.set_ease(Tween.EASE_OUT)

		tile.z_index = 5 if motion["merged"] else 4
		tween.tween_property(tile, "position", _cell_position(to_pos), MOVE_DURATION)
		animated_count += 1

	if animated_count > 0:
		await tween.finished


func _animate_clears(cleared_positions: Array[Vector2i]) -> void:
	var tween: Tween = null
	var animated_count := 0

	for pos in cleared_positions:
		var tile = tiles_by_pos.get(pos)
		if not is_instance_valid(tile):
			continue

		if tween == null:
			tween = create_tween()
			tween.set_parallel(true)
			tween.set_trans(Tween.TRANS_QUAD)
			tween.set_ease(Tween.EASE_OUT)

		tile.pivot_offset = tile.size * 0.5
		tween.tween_property(tile, "scale", Vector2(1.18, 1.18), CLEAR_DURATION)
		tween.tween_property(tile, "modulate:a", 0.0, CLEAR_DURATION)
		animated_count += 1

	if animated_count > 0:
		await tween.finished


func _render_board(spawn_positions: Array[Vector2i] = [], pop_positions: Array[Vector2i] = []) -> void:
	for tile in tile_nodes:
		if is_instance_valid(tile):
			tile.queue_free()
	tile_nodes.clear()
	tiles_by_pos.clear()

	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var tile_value: int = board[y][x]
			if tile_value == 0:
				continue

			var tile = TileScript.new()
			tile.z_index = 2
			board_panel.add_child(tile)
			tile.size = Vector2(cell_size, cell_size)
			tile.position = _cell_position(Vector2i(x, y))
			tile.set_value(tile_value)
			tile_nodes.append(tile)
			tiles_by_pos[Vector2i(x, y)] = tile

			var tile_pos := Vector2i(x, y)
			if spawn_positions.has(tile_pos):
				tile.spawn()
			elif pop_positions.has(tile_pos):
				tile.pop()


func _update_stats() -> void:
	score_label.text = "SCORE\n%d" % score
	best_label.text = "BEST\n%d" % best_score
	combo_label.text = "COMBO\nx%d" % combo


func _update_status(merges: int, cleared: int) -> void:
	if cleared > 0:
		status_label.text = "POP x%d  /  COMBO x%d" % [cleared, combo]
	elif merges > 0:
		status_label.text = "MERGE x%d" % merges
	else:
		status_label.text = "SLIDE"


func _shake_board() -> void:
	var home := board_panel.position
	var tween := create_tween()
	tween.tween_property(board_panel, "position", home + Vector2(7.0, 0.0), 0.025)
	tween.tween_property(board_panel, "position", home - Vector2(7.0, 0.0), 0.05)
	tween.tween_property(board_panel, "position", home, 0.025)


func _spawn_random_tile() -> Dictionary:
	var empty_positions: Array[Vector2i] = []
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if board[y][x] == 0:
				empty_positions.append(Vector2i(x, y))

	if empty_positions.is_empty():
		return {
			"spawned": false,
			"position": Vector2i(-1, -1),
		}

	var pos := empty_positions[rng.randi_range(0, empty_positions.size() - 1)]
	board[pos.y][pos.x] = 2 if rng.randf() < 0.86 else 4
	return {
		"spawned": true,
		"position": pos,
	}


func _has_any_move() -> bool:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if board[y][x] == 0:
				return true

			var pos := Vector2i(x, y)
			var right_neighbor := pos + DIR_RIGHT
			if _inside_board(right_neighbor) and board[right_neighbor.y][right_neighbor.x] == board[y][x]:
				return true

			var down_neighbor := pos + DIR_DOWN
			if _inside_board(down_neighbor) and board[down_neighbor.y][down_neighbor.x] == board[y][x]:
				return true

	return false


func _empty_board() -> Array:
	var empty := []
	for y in range(BOARD_SIZE):
		var row := []
		for x in range(BOARD_SIZE):
			row.append(0)
		empty.append(row)
	return empty


func _boards_equal(first: Array, second: Array) -> bool:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if first[y][x] != second[y][x]:
				return false
	return true


func _inside_board(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_SIZE and pos.y >= 0 and pos.y < BOARD_SIZE


func _cell_position(pos: Vector2i) -> Vector2:
	return Vector2(
		BOARD_PADDING + float(pos.x) * (cell_size + TILE_GAP),
		BOARD_PADDING + float(pos.y) * (cell_size + TILE_GAP)
	)
