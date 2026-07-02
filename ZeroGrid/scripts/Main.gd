## Main gameplay controller for ZeroGrid.
##
## Owns the board state, keyboard input, turn resolution, pressure system,
## warning cells, spawning rules, scoring, and top-level UI layout.
extends Control

const TileScript := preload("res://scripts/Tile.gd")

# Board, merge, and layout tuning.
const BOARD_SIZE := 6
const CLEAR_VALUE := 32
const START_TILES := 3
const BOARD_PADDING := 12.0
const TILE_GAP := 10.0

# Animation timings are intentionally short to keep repeated keyboard input snappy.
const MOVE_DURATION := 0.14
const MERGE_SETTLE_DURATION := 0.16
const CLEAR_DURATION := 0.22

# Pressure is a one-way heat meter. Pops clear space, but do not reduce pressure.
const PRESSURE_MAX := 160
const PRESSURE_PER_MOVE := 10
const PRESSURE_OVERLOAD_RESET := 120
const PRESSURE_OVERLOAD_EXTRA_SPAWNS := 3

# Warning cells telegraph future forced spawns at high pressure.
const WARNING_PRESSURE := 90
const WARNING_HIGH_PRESSURE := 125
const WARNING_LOW_COUNT := 1
const WARNING_HIGH_COUNT := 2

# Spawn tables become harsher as pressure crosses these thresholds.
const SPAWN_MID_PRESSURE := 50
const SPAWN_HIGH_PRESSURE := 90
const SPAWN_EXTREME_PRESSURE := 125

# Direction constants keep the input, movement planner, and board checks aligned.
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

# Core run state.
var rng := RandomNumberGenerator.new()
var board := []
var score := 0
var best_score := 0
var moves := 0
var combo := 0
var pressure := 0
var game_over := false
var is_animating := false
var queued_direction := Vector2i.ZERO
var warning_positions: Array[Vector2i] = []
var cell_size := 64.0

# UI node references created in code so the prototype stays scene-light.
var background: ColorRect
var title_label: Label
var rule_label: Label
var score_label: Label
var best_label: Label
var combo_label: Label
var pressure_label: Label
var pressure_track: Panel
var pressure_fill: Panel
var status_label: Label
var board_panel: Panel
var cell_nodes: Array[Panel] = []
var tile_nodes := []
var tiles_by_pos := {}


## Initializes the procedural UI and starts a fresh run.
func _ready() -> void:
	rng.randomize()
	_build_ui()
	_new_game()
	resized.connect(_layout)
	call_deferred("_layout")


## Routes keyboard input into movement, restart, or input buffering.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	match key_event.keycode:
		KEY_LEFT, KEY_A:
			_handle_move_input(DIR_LEFT)
		KEY_RIGHT, KEY_D:
			_handle_move_input(DIR_RIGHT)
		KEY_UP, KEY_W:
			_handle_move_input(DIR_UP)
		KEY_DOWN, KEY_S:
			_handle_move_input(DIR_DOWN)
		KEY_R:
			if not is_animating:
				_new_game()


## Builds all UI nodes that are stable across the whole game session.
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

	pressure_label = _make_label("PRESSURE 0%", 14, Color("#c8d4e1"), HORIZONTAL_ALIGNMENT_LEFT)
	add_child(pressure_label)

	pressure_track = Panel.new()
	var pressure_track_style := StyleBoxFlat.new()
	pressure_track_style.bg_color = Color("#101820")
	pressure_track_style.border_color = Color("#34475d")
	pressure_track_style.border_width_left = 1
	pressure_track_style.border_width_top = 1
	pressure_track_style.border_width_right = 1
	pressure_track_style.border_width_bottom = 1
	pressure_track_style.corner_radius_top_left = 7
	pressure_track_style.corner_radius_top_right = 7
	pressure_track_style.corner_radius_bottom_left = 7
	pressure_track_style.corner_radius_bottom_right = 7
	pressure_track.add_theme_stylebox_override("panel", pressure_track_style)
	add_child(pressure_track)

	pressure_fill = Panel.new()
	pressure_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pressure_track.add_child(pressure_fill)

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
		_apply_cell_style(cell, false)
		board_panel.add_child(cell)
		cell_nodes.append(cell)

	status_label = _make_label("", 20, Color("#f4d68c"), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(status_label)


## Creates a configured label with the shared prototype text style.
func _make_label(text: String, font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Creates the compact score/best/combo stat labels.
func _make_stat_label() -> Label:
	var label := _make_label("", 18, Color("#e7eef7"), HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_font_size_override("font_size", 18)
	return label


## Reflows the board and HUD for the current window size.
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

	pressure_label.position = Vector2(margin, 96.0)
	pressure_label.size = Vector2(112.0, 20.0)

	var pressure_track_x := margin + 116.0
	var pressure_track_width: float = min(360.0, max(140.0, score_label.position.x - pressure_track_x - 20.0))
	pressure_track.position = Vector2(pressure_track_x, 101.0)
	pressure_track.size = Vector2(pressure_track_width, 12.0)

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

	for rendered_tile in tile_nodes:
		if is_instance_valid(rendered_tile):
			rendered_tile.size = Vector2(cell_size, cell_size)

	if not is_animating:
		for pos in tiles_by_pos.keys():
			var positioned_tile = tiles_by_pos[pos]
			if is_instance_valid(positioned_tile):
				positioned_tile.position = _cell_position(pos as Vector2i)

	_update_pressure_ui()


## Resets all gameplay state and seeds the opening bubbles.
func _new_game() -> void:
	is_animating = false
	queued_direction = Vector2i.ZERO
	warning_positions.clear()
	board = _empty_board()
	score = 0
	moves = 0
	combo = 0
	pressure = 0
	game_over = false
	status_label.text = "READY"

	var spawn_positions: Array[Vector2i] = []
	for i in range(START_TILES):
		var spawn_result: Dictionary = _spawn_random_tile()
		if spawn_result["spawned"]:
			spawn_positions.append(spawn_result["position"])

	_render_board(spawn_positions)
	_update_stats()
	_update_warning_cells()


## Resolves one full turn: slide, merge, pop, spawn, warning refresh, and game-over check.
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
	_add_pressure(PRESSURE_PER_MOVE)

	_render_board([], result["merge_positions"])
	_update_stats()
	if _has_clear_ready(result["merge_positions"]):
		await get_tree().create_timer(MERGE_SETTLE_DURATION).timeout

	var cleared_positions: Array[Vector2i] = []
	_resolve_clears(cleared_positions)
	if cleared_positions.is_empty():
		combo = 0
	else:
		combo += 1
		score += cleared_positions.size() * 25 * combo
		_shake_board()
		_update_stats()
		_update_status(result["merges"], cleared_positions.size(), 0)
		await _animate_clears(cleared_positions)
		_render_board()

	var spawn_positions: Array[Vector2i] = []
	var warning_spawns := _spawn_warning_tiles(spawn_positions)
	var spawn_result := _spawn_random_tile()
	if spawn_result["spawned"]:
		spawn_positions.append(spawn_result["position"])
	var overload_spawns := _spawn_pressure_overload(spawn_positions)
	_refresh_warning_cells()

	best_score = max(best_score, score)

	_render_board(spawn_positions)
	_update_stats()
	_update_status(result["merges"], cleared_positions.size(), overload_spawns, warning_spawns)

	if not _has_any_move():
		game_over = true
		status_label.text = "GAME OVER  /  R"

	is_animating = false
	_consume_queued_direction()


## Plans a 2048-style slide without mutating the live board.
## Returns the next board plus motion data so tiles can animate before state commits.
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


## Buffers the latest direction if a turn animation is still resolving.
func _handle_move_input(direction: Vector2i) -> void:
	if is_animating:
		queued_direction = direction
		return

	_try_move(direction)


## Runs the last buffered direction immediately after the current turn unlocks input.
func _consume_queued_direction() -> void:
	if queued_direction == Vector2i.ZERO or game_over:
		return

	var next_direction := queued_direction
	queued_direction = Vector2i.ZERO
	call_deferred("_try_move", next_direction)


## Checks whether any newly merged tile is about to become a burst.
func _has_clear_ready(merge_positions: Array[Vector2i]) -> bool:
	for pos in merge_positions:
		if board[pos.y][pos.x] >= CLEAR_VALUE:
			return true
	return false


## Applies the regular or warning visual style to one board cell.
func _apply_cell_style(cell: Panel, is_warning: bool) -> void:
	var cell_style := StyleBoxFlat.new()
	cell_style.bg_color = Color("#3a1c29") if is_warning else Color("#182435")
	cell_style.border_color = Color("#ff695f") if is_warning else Color(1.0, 1.0, 1.0, 0.05)
	cell_style.border_width_left = 2 if is_warning else 1
	cell_style.border_width_top = 2 if is_warning else 1
	cell_style.border_width_right = 2 if is_warning else 1
	cell_style.border_width_bottom = 2 if is_warning else 1
	cell_style.corner_radius_top_left = 8
	cell_style.corner_radius_top_right = 8
	cell_style.corner_radius_bottom_left = 8
	cell_style.corner_radius_bottom_right = 8
	cell.add_theme_stylebox_override("panel", cell_style)


## Returns a line of board coordinates in the order a slide should consume them.
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


## Finds all burst tiles and adjacent low-value bubbles, clears them, and awards clear score.
func _resolve_clears(cleared: Array[Vector2i]) -> int:
	var clear_map := {}
	var burst_count := 0

	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var tile_value: int = board[y][x]
			if tile_value < CLEAR_VALUE:
				continue

			var origin := Vector2i(x, y)
			burst_count += 1
			clear_map[origin] = true
			for offset in NEIGHBORS:
				var neighbor: Vector2i = origin + offset
				if _inside_board(neighbor) and board[neighbor.y][neighbor.x] > 0 and board[neighbor.y][neighbor.x] <= tile_value / 2:
					clear_map[neighbor] = true

	for pos in clear_map.keys():
		var clear_pos := pos as Vector2i
		var cleared_value: int = board[clear_pos.y][clear_pos.x]
		if cleared_value == 0:
			continue
		score += cleared_value
		board[clear_pos.y][clear_pos.x] = 0
		cleared.append(clear_pos)

	return burst_count


## Animates every existing tile from its old cell to its planned destination.
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


## Plays the burst fade/scale animation before cleared tiles are removed from the board.
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


## Rebuilds the visible tile nodes from the board array.
## The board is small, so full redraws keep prototype state simple and reliable.
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


## Updates score labels and pressure UI after gameplay state changes.
func _update_stats() -> void:
	score_label.text = "SCORE\n%d" % score
	best_label.text = "BEST\n%d" % best_score
	combo_label.text = "COMBO\nx%d" % combo
	_update_pressure_ui()


## Shows the highest-priority turn result message.
func _update_status(merges: int, cleared: int, overload_spawns: int = 0, warning_spawns: int = 0) -> void:
	if cleared > 0:
		status_label.text = "POP x%d  /  COMBO x%d" % [cleared, combo]
	elif overload_spawns > 0:
		status_label.text = "OVERLOAD  +%d" % overload_spawns
	elif warning_spawns > 0:
		status_label.text = "WARNING  +%d" % warning_spawns
	elif merges > 0:
		status_label.text = "MERGE x%d" % merges
	else:
		status_label.text = "SLIDE"


## Adds a short board shake to make bursts and pressure events feel physical.
func _shake_board() -> void:
	var home := board_panel.position
	var tween := create_tween()
	tween.tween_property(board_panel, "position", home + Vector2(7.0, 0.0), 0.025)
	tween.tween_property(board_panel, "position", home - Vector2(7.0, 0.0), 0.05)
	tween.tween_property(board_panel, "position", home, 0.025)


## Increases pressure while clamping to the current pressure cap.
func _add_pressure(amount: int) -> void:
	pressure = clampi(pressure + amount, 0, PRESSURE_MAX)


## Applies overload: spawn extra bubbles and roll pressure back to the overload floor.
func _spawn_pressure_overload(spawn_positions: Array[Vector2i]) -> int:
	if pressure < PRESSURE_MAX:
		return 0

	pressure = PRESSURE_OVERLOAD_RESET
	var spawned_count := 0
	for i in range(PRESSURE_OVERLOAD_EXTRA_SPAWNS):
		var spawn_result := _spawn_random_tile()
		if spawn_result["spawned"]:
			spawn_positions.append(spawn_result["position"])
			spawned_count += 1

	return spawned_count


## Converts previous-turn warning cells into forced spawns if those cells stayed empty.
func _spawn_warning_tiles(spawn_positions: Array[Vector2i]) -> int:
	var spawned_count := 0
	for pos in warning_positions:
		if not _inside_board(pos):
			continue
		if board[pos.y][pos.x] != 0:
			continue

		board[pos.y][pos.x] = _random_spawn_value()
		spawn_positions.append(pos)
		spawned_count += 1

	warning_positions.clear()
	_update_warning_cells()
	return spawned_count


## Selects new warning cells based on the current pressure tier.
func _refresh_warning_cells() -> void:
	warning_positions.clear()

	if pressure < WARNING_PRESSURE:
		_update_warning_cells()
		return

	var empty_positions := _empty_positions()
	var warning_count := WARNING_HIGH_COUNT if pressure >= WARNING_HIGH_PRESSURE else WARNING_LOW_COUNT
	for i in range(warning_count):
		if empty_positions.is_empty():
			break
		var index := rng.randi_range(0, empty_positions.size() - 1)
		warning_positions.append(empty_positions[index])
		empty_positions.remove_at(index)

	_update_warning_cells()


## Repaints all board cells so warning state is visible before the next move.
func _update_warning_cells() -> void:
	if cell_nodes.is_empty():
		return

	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			var pos := Vector2i(x, y)
			var index := y * BOARD_SIZE + x
			_apply_cell_style(cell_nodes[index], warning_positions.has(pos))


## Updates pressure label, bar fill, color, and background heat tint.
func _update_pressure_ui() -> void:
	if pressure_label == null or pressure_fill == null or pressure_track == null:
		return

	var ratio: float = clamp(float(pressure) / float(PRESSURE_MAX), 0.0, 1.0)
	var color: Color = _pressure_color(ratio)
	pressure_label.text = "PRESSURE %d/%d" % [pressure, PRESSURE_MAX]
	pressure_label.add_theme_color_override("font_color", color)

	pressure_fill.position = Vector2.ZERO
	var fill_width: float = 0.0 if ratio <= 0.0 else max(2.0, pressure_track.size.x * ratio)
	pressure_fill.size = Vector2(fill_width, pressure_track.size.y)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = color
	fill_style.corner_radius_top_left = 7
	fill_style.corner_radius_top_right = 7
	fill_style.corner_radius_bottom_left = 7
	fill_style.corner_radius_bottom_right = 7
	pressure_fill.add_theme_stylebox_override("panel", fill_style)

	background.color = Color("#111923").lerp(Color("#24151d"), ratio)


## Maps pressure ratio to a blue -> yellow -> red danger color.
func _pressure_color(ratio: float) -> Color:
	if ratio < 0.5:
		return Color("#75d7ff").lerp(Color("#f4d66f"), ratio * 2.0)
	return Color("#f4d66f").lerp(Color("#ff5a5f"), (ratio - 0.5) * 2.0)


## Returns the next spawned bubble value using the pressure-dependent spawn table.
func _random_spawn_value() -> int:
	var roll := rng.randf()

	if pressure >= SPAWN_EXTREME_PRESSURE:
		if roll < 0.28:
			return 2
		if roll < 0.74:
			return 4
		if roll < 0.96:
			return 8
		return 16

	if pressure >= SPAWN_HIGH_PRESSURE:
		if roll < 0.48:
			return 2
		if roll < 0.88:
			return 4
		return 8

	if pressure >= SPAWN_MID_PRESSURE:
		return 4 if roll < 0.30 else 2

	return 4 if roll < 0.12 else 2


## Spawns one random bubble in an empty cell.
func _spawn_random_tile() -> Dictionary:
	var empty_positions := _empty_positions()

	if empty_positions.is_empty():
		return {
			"spawned": false,
			"position": Vector2i(-1, -1),
		}

	var pos := empty_positions[rng.randi_range(0, empty_positions.size() - 1)]
	board[pos.y][pos.x] = _random_spawn_value()
	return {
		"spawned": true,
		"position": pos,
	}


## Checks whether the current board has any empty cell or adjacent merge pair.
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


## Lists all currently empty board coordinates.
func _empty_positions() -> Array[Vector2i]:
	var empty_positions: Array[Vector2i] = []
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if board[y][x] == 0:
				empty_positions.append(Vector2i(x, y))
	return empty_positions


## Creates a fresh zero-filled board array.
func _empty_board() -> Array:
	var empty := []
	for y in range(BOARD_SIZE):
		var row := []
		for x in range(BOARD_SIZE):
			row.append(0)
		empty.append(row)
	return empty


## Compares two board arrays cell by cell.
func _boards_equal(first: Array, second: Array) -> bool:
	for y in range(BOARD_SIZE):
		for x in range(BOARD_SIZE):
			if first[y][x] != second[y][x]:
				return false
	return true


## Returns true when a board coordinate is within the grid.
func _inside_board(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < BOARD_SIZE and pos.y >= 0 and pos.y < BOARD_SIZE


## Converts a board coordinate to a local pixel position inside the board panel.
func _cell_position(pos: Vector2i) -> Vector2:
	return Vector2(
		BOARD_PADDING + float(pos.x) * (cell_size + TILE_GAP),
		BOARD_PADDING + float(pos.y) * (cell_size + TILE_GAP)
	)
