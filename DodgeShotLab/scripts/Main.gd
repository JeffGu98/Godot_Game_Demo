## Main gameplay controller for Dodge Shot Lab.
##
## Owns the run state, spawning, auto-fire weapon rules, collision resolution,
## score tracking, local leaderboard, and top-level HUD layout.
extends Node2D

const PlayerScript := preload("res://scripts/Player.gd")
const EnemyScript := preload("res://scripts/Enemy.gd")
const PlayerBulletScript := preload("res://scripts/PlayerBullet.gd")
const EnemyBulletScript := preload("res://scripts/EnemyBullet.gd")
const PickupScript := preload("res://scripts/Pickup.gd")
const BurstEffectScript := preload("res://scripts/BurstEffect.gd")

# Run and layout tuning.
const LEADERBOARD_PATH := "user://dodge_shot_lab_scores.cfg"
const MAX_LEADERBOARD_ENTRIES := 5
const MAX_WEAPON_LEVEL := 5
const PLAY_MARGIN_X := 44.0
const PLAY_TOP := 92.0
const PLAY_BOTTOM_MARGIN := 34.0
const PLAYER_MAX_HP := 3
const PLAYER_COLLISION_RADIUS := 14.0

# Spawn cadence. These values deliberately create pressure before weapon power
# ramps too high, because movement tension is the prototype's main question.
const BASE_ENEMY_INTERVAL := 1.14
const MIN_ENEMY_INTERVAL := 0.34
const FIRST_PICKUP_TIME := 5.0
const PICKUP_INTERVAL_MIN := 7.0
const PICKUP_INTERVAL_MAX := 10.5

const WEAPON_TYPES := ["needle", "fan", "pulse", "rail", "orbit"]

var rng := RandomNumberGenerator.new()
var play_area := Rect2()
var last_viewport_size := Vector2.ZERO

var player = null
var enemies := []
var player_bullets := []
var enemy_bullets := []
var pickups := []

var current_weapon := "needle"
var weapon_level := 0
var fire_timer := 0.0
var enemy_spawn_timer := 0.0
var pickup_spawn_timer := FIRST_PICKUP_TIME
var orbit_angle := 0.0
var orbit_hit_cooldowns := {}

var score := 0
var kill_score := 0
var survival_time := 0.0
var game_over := false
var score_recorded := false
var leaderboard := []

var hud_layer: CanvasLayer
var title_label: Label
var score_label: Label
var hp_label: Label
var weapon_label: Label
var time_label: Label
var status_label: Label
var leaderboard_label: Label
var help_label: Label


## Initializes the procedural scene and starts a new run.
func _ready() -> void:
	rng.randomize()
	_build_ui()
	_load_leaderboard()
	_layout()
	_new_game()


## Handles restart input separately from movement-only gameplay.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_R and game_over:
		_new_game()


## Runs the active game loop.
func _process(delta: float) -> void:
	if get_viewport_rect().size != last_viewport_size:
		_layout()

	if game_over:
		queue_redraw()
		return

	survival_time += delta
	score = int(survival_time * 10.0) + kill_score

	player.play_area = play_area
	player.move_from_input(delta)

	_update_enemy_spawns(delta)
	_update_pickup_spawns(delta)
	_update_auto_fire(delta)
	_update_enemies(delta)
	_update_pickups()
	_update_player_bullet_hits()
	_update_orbit_attack(delta)
	_update_player_damage()
	_cleanup_nodes()
	_update_ui()
	queue_redraw()


## Draws the playfield and orbit weapon preview behind gameplay actors.
func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("#070b11"), true)
	draw_rect(play_area, Color("#0d1622"), true)
	draw_rect(play_area, Color("#2b435d"), false, 2.0, true)

	var lane_color := Color("#1a2a3d")
	for i in range(1, 4):
		var x := lerpf(play_area.position.x, play_area.end.x, float(i) / 4.0)
		draw_line(Vector2(x, play_area.position.y), Vector2(x, play_area.end.y), lane_color, 1.0)

	if not game_over and current_weapon == "orbit" and player != null:
		for point in _orbit_positions():
			draw_circle(point, 7.0, _weapon_color("orbit"))
			draw_arc(point, 10.0, 0.0, TAU, 20, Color("#ffffff"), 1.2, true)


## Builds all HUD labels used by the prototype.
func _build_ui() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)

	title_label = _make_label("DODGE SHOT LAB", 26, Color("#f5f1dd"), HORIZONTAL_ALIGNMENT_LEFT)
	hud_layer.add_child(title_label)

	score_label = _make_label("", 18, Color("#f8f5d8"), HORIZONTAL_ALIGNMENT_LEFT)
	hud_layer.add_child(score_label)

	hp_label = _make_label("", 18, Color("#9be7ff"), HORIZONTAL_ALIGNMENT_LEFT)
	hud_layer.add_child(hp_label)

	weapon_label = _make_label("", 18, Color("#f2c66d"), HORIZONTAL_ALIGNMENT_LEFT)
	hud_layer.add_child(weapon_label)

	time_label = _make_label("", 18, Color("#c4d1e1"), HORIZONTAL_ALIGNMENT_RIGHT)
	hud_layer.add_child(time_label)

	status_label = _make_label("", 18, Color("#ffcf6d"), HORIZONTAL_ALIGNMENT_CENTER)
	hud_layer.add_child(status_label)

	leaderboard_label = _make_label("", 15, Color("#aebdd0"), HORIZONTAL_ALIGNMENT_RIGHT)
	hud_layer.add_child(leaderboard_label)

	help_label = _make_label("MOVE: WASD / ARROWS    AUTO FIRE    R: RESTART AFTER GAME OVER", 14, Color("#71849c"), HORIZONTAL_ALIGNMENT_CENTER)
	hud_layer.add_child(help_label)


## Creates one HUD label with the shared visual style.
func _make_label(text: String, font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Recomputes the play area and HUD positions for the current window size.
func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	last_viewport_size = viewport_size
	play_area = Rect2(
		Vector2(PLAY_MARGIN_X, PLAY_TOP),
		Vector2(max(320.0, viewport_size.x - PLAY_MARGIN_X * 2.0), max(360.0, viewport_size.y - PLAY_TOP - PLAY_BOTTOM_MARGIN))
	)

	title_label.position = Vector2(28.0, 18.0)
	title_label.size = Vector2(280.0, 34.0)

	score_label.position = Vector2(30.0, 54.0)
	score_label.size = Vector2(150.0, 28.0)

	hp_label.position = Vector2(190.0, 54.0)
	hp_label.size = Vector2(100.0, 28.0)

	weapon_label.position = Vector2(302.0, 54.0)
	weapon_label.size = Vector2(360.0, 28.0)

	time_label.position = Vector2(viewport_size.x - 196.0, 18.0)
	time_label.size = Vector2(166.0, 28.0)

	leaderboard_label.position = Vector2(viewport_size.x - 248.0, 48.0)
	leaderboard_label.size = Vector2(218.0, 112.0)

	status_label.position = Vector2(play_area.position.x, play_area.end.y + 5.0)
	status_label.size = Vector2(play_area.size.x, 26.0)

	help_label.position = Vector2(play_area.position.x, viewport_size.y - 28.0)
	help_label.size = Vector2(play_area.size.x, 22.0)

	if player != null:
		player.play_area = play_area
		player.position.x = clampf(player.position.x, play_area.position.x + PLAYER_COLLISION_RADIUS, play_area.end.x - PLAYER_COLLISION_RADIUS)
		player.position.y = clampf(player.position.y, play_area.position.y + PLAYER_COLLISION_RADIUS, play_area.end.y - PLAYER_COLLISION_RADIUS)

	queue_redraw()


## Clears previous run objects and starts from a slow single Needle shot.
func _new_game() -> void:
	_clear_gameplay_nodes()

	current_weapon = "needle"
	weapon_level = 0
	fire_timer = 0.25
	enemy_spawn_timer = 0.45
	pickup_spawn_timer = FIRST_PICKUP_TIME
	orbit_angle = 0.0
	orbit_hit_cooldowns.clear()

	score = 0
	kill_score = 0
	survival_time = 0.0
	game_over = false
	score_recorded = false

	player = PlayerScript.new()
	player.z_index = 20
	add_child(player)
	player.reset(Vector2(play_area.get_center().x, play_area.end.y - 62.0), play_area)

	status_label.text = "SURVIVE / GROUP / CLEAR"
	_update_ui()
	queue_redraw()


## Updates score, health, weapon, time, and leaderboard labels.
func _update_ui() -> void:
	score_label.text = "SCORE  %d" % score
	hp_label.text = "HP  %d/%d" % [player.hp if player != null else 0, PLAYER_MAX_HP]
	weapon_label.text = "WEAPON  %s  LV %d" % [_weapon_label(current_weapon), weapon_level]
	time_label.text = "TIME  %.1f" % survival_time
	leaderboard_label.text = _leaderboard_text()


## Spawns enemies faster over time while keeping the pressure readable.
func _update_enemy_spawns(delta: float) -> void:
	enemy_spawn_timer -= delta
	if enemy_spawn_timer > 0.0:
		return

	_spawn_enemy(_choose_enemy_type())
	var pressure: float = clampf(survival_time / 70.0, 0.0, 1.0)
	var next_interval := lerpf(BASE_ENEMY_INTERVAL, MIN_ENEMY_INTERVAL, pressure)
	enemy_spawn_timer = rng.randf_range(next_interval * 0.72, next_interval * 1.18)


## Periodically creates weapon packages that force upgrade-or-switch decisions.
func _update_pickup_spawns(delta: float) -> void:
	pickup_spawn_timer -= delta
	if pickup_spawn_timer > 0.0:
		return

	_spawn_pickup()
	pickup_spawn_timer = rng.randf_range(PICKUP_INTERVAL_MIN, PICKUP_INTERVAL_MAX)


## Advances enemies and lets shooter enemies fire aimed bullets.
func _update_enemies(delta: float) -> void:
	for enemy in enemies.duplicate():
		if not _is_live_node(enemy):
			continue

		enemy.advance(delta, player.position)
		if enemy.should_fire(delta):
			_spawn_enemy_bullet(enemy)

		if enemy.position.y > play_area.end.y + enemy.radius:
			_remove_enemy(enemy)
			_damage_player("BREACH")


## Applies pickups on contact and removes missed packages.
func _update_pickups() -> void:
	for pickup in pickups.duplicate():
		if not _is_live_node(pickup):
			continue

		if pickup.position.distance_to(player.position) <= pickup.radius + PLAYER_COLLISION_RADIUS:
			_apply_pickup(pickup)
			pickup.queue_free()
		elif pickup.position.y > play_area.end.y + pickup.radius + 24.0:
			pickup.queue_free()


## Fires the active weapon automatically when its cooldown is ready.
func _update_auto_fire(delta: float) -> void:
	if current_weapon == "orbit":
		return

	fire_timer -= delta
	if fire_timer > 0.0:
		return

	_fire_current_weapon()
	fire_timer = float(_weapon_stats().get("cooldown", 0.8))


## Applies player bullet damage against enemies.
func _update_player_bullet_hits() -> void:
	for bullet in player_bullets.duplicate():
		if not _is_live_node(bullet):
			continue

		for enemy in enemies.duplicate():
			if not _is_live_node(enemy):
				continue
			if bullet.try_hit(enemy):
				_spawn_burst(enemy.position, bullet.bullet_color, 18.0, 0.16)
				if enemy.take_damage(bullet.damage):
					_kill_enemy(enemy)


## Applies Orbit weapon contact damage around the player.
func _update_orbit_attack(delta: float) -> void:
	for enemy_id in orbit_hit_cooldowns.keys():
		orbit_hit_cooldowns[enemy_id] = float(orbit_hit_cooldowns[enemy_id]) - delta
		if float(orbit_hit_cooldowns[enemy_id]) <= 0.0:
			orbit_hit_cooldowns.erase(enemy_id)

	if current_weapon != "orbit":
		return

	orbit_angle += delta * (3.1 + float(weapon_level) * 0.25)
	var stats := _orbit_stats()
	var hit_interval := float(stats.get("hit_interval", 0.35))
	var damage := int(stats.get("damage", 1))
	var blade_radius := float(stats.get("blade_radius", 8.0))
	var orbit_points := _orbit_positions()

	for enemy in enemies.duplicate():
		if not _is_live_node(enemy):
			continue

		var enemy_id: int = enemy.get_instance_id()
		if orbit_hit_cooldowns.has(enemy_id):
			continue

		for point in orbit_points:
			if point.distance_to(enemy.position) <= enemy.radius + blade_radius:
				orbit_hit_cooldowns[enemy_id] = hit_interval
				_spawn_burst(enemy.position, _weapon_color("orbit"), 18.0, 0.14)
				if enemy.take_damage(damage):
					_kill_enemy(enemy)
				break


## Resolves collisions between the player, enemy bodies, and enemy bullets.
func _update_player_damage() -> void:
	for enemy in enemies.duplicate():
		if not _is_live_node(enemy):
			continue
		if enemy.position.distance_to(player.position) <= enemy.radius + PLAYER_COLLISION_RADIUS:
			_damage_player("COLLISION")
			_remove_enemy(enemy)

	for bullet in enemy_bullets.duplicate():
		if not _is_live_node(bullet):
			continue
		if bullet.position.distance_to(player.position) <= bullet.radius + PLAYER_COLLISION_RADIUS:
			_damage_player("HIT")
			bullet.queue_free()


## Deletes offscreen objects and compacts tracking arrays.
func _cleanup_nodes() -> void:
	for bullet in player_bullets:
		if _is_live_node(bullet) and _outside_play_area(bullet.position, 140.0):
			bullet.queue_free()

	for bullet in enemy_bullets:
		if _is_live_node(bullet) and _outside_play_area(bullet.position, 80.0):
			bullet.queue_free()

	enemies = _compact_node_array(enemies)
	player_bullets = _compact_node_array(player_bullets)
	enemy_bullets = _compact_node_array(enemy_bullets)
	pickups = _compact_node_array(pickups)


## Creates one enemy at the top of the playfield.
func _spawn_enemy(enemy_kind: String) -> void:
	var enemy = EnemyScript.new()
	enemy.configure(enemy_kind, survival_time / 28.0)
	enemy.position = Vector2(
		rng.randf_range(play_area.position.x + 30.0, play_area.end.x - 30.0),
		play_area.position.y - 34.0
	)
	enemy.z_index = 8
	add_child(enemy)
	enemies.append(enemy)


## Chooses enemy types by elapsed time so new threats enter gradually.
func _choose_enemy_type() -> String:
	var candidates := ["wisp"]
	var weights := [48.0]

	if survival_time >= 5.0:
		candidates.append("charger")
		weights.append(22.0)
	if survival_time >= 12.0:
		candidates.append("spitter")
		weights.append(18.0)
	if survival_time >= 20.0:
		candidates.append("splitter")
		weights.append(16.0)
	if survival_time >= 30.0:
		candidates.append("bulwark")
		weights.append(12.0)

	var total := 0.0
	for weight in weights:
		total += weight

	var roll := rng.randf_range(0.0, total)
	var cursor := 0.0
	for i in range(candidates.size()):
		cursor += float(weights[i])
		if roll <= cursor:
			return candidates[i]

	return "wisp"


## Spawns a single aimed enemy bullet.
func _spawn_enemy_bullet(enemy) -> void:
	var direction: Vector2 = (player.position - enemy.position).normalized()
	if direction.length_squared() == 0.0:
		direction = Vector2.DOWN

	var bullet = EnemyBulletScript.new()
	bullet.position = enemy.position
	bullet.z_index = 12
	bullet.configure(direction * enemy.shoot_speed, 6.0)
	add_child(bullet)
	enemy_bullets.append(bullet)


## Creates a random weapon package in the upper half of the playfield.
func _spawn_pickup() -> void:
	var weapon_type: String = WEAPON_TYPES[rng.randi_range(0, WEAPON_TYPES.size() - 1)]
	var pickup = PickupScript.new()
	pickup.position = Vector2(
		rng.randf_range(play_area.position.x + 30.0, play_area.end.x - 30.0),
		rng.randf_range(play_area.position.y + 24.0, play_area.position.y + play_area.size.y * 0.42)
	)
	pickup.z_index = 16
	pickup.configure(weapon_type, _weapon_color(weapon_type))
	add_child(pickup)
	pickups.append(pickup)
	status_label.text = "PACKAGE  %s" % _weapon_label(weapon_type)


## Applies the upgrade-or-switch weapon package rule.
func _apply_pickup(pickup) -> void:
	if pickup.weapon_type == current_weapon:
		weapon_level = min(MAX_WEAPON_LEVEL, weapon_level + 1)
		status_label.text = "%s UPGRADE  LV %d" % [_weapon_label(current_weapon), weapon_level]
	else:
		current_weapon = pickup.weapon_type
		weapon_level = 0
		fire_timer = 0.0
		orbit_hit_cooldowns.clear()
		status_label.text = "SWITCH  %s  LV 0" % _weapon_label(current_weapon)

	_spawn_burst(player.position, _weapon_color(current_weapon), 34.0, 0.22)


## Creates all projectiles for the currently equipped non-orbit weapon.
func _fire_current_weapon() -> void:
	var stats := _weapon_stats()
	match current_weapon:
		"fan":
			var shot_count := int(stats.get("shots", 3))
			var spread := deg_to_rad(float(stats.get("spread_degrees", 28.0)))
			for i in range(shot_count):
				var t := 0.5 if shot_count == 1 else float(i) / float(shot_count - 1)
				var angle := lerpf(-spread, spread, t)
				var direction := Vector2.UP.rotated(angle)
				_spawn_player_bullet({
					"kind": "fan",
					"damage": stats.get("damage", 1),
					"radius": 4.2,
					"velocity": direction * float(stats.get("speed", 420.0)),
					"life_time": 1.55,
					"pierce": 0,
					"color": _weapon_color("fan"),
				}, player.position + Vector2(0.0, -PLAYER_COLLISION_RADIUS))
		"pulse":
			_spawn_player_bullet({
				"kind": "pulse",
				"damage": stats.get("damage", 1),
				"radius": 12.0,
				"velocity": Vector2.ZERO,
				"life_time": 0.38,
				"pierce": 99,
				"pulse_max_radius": stats.get("pulse_radius", 96.0),
				"pulse_expand_speed": stats.get("pulse_speed", 320.0),
				"color": _weapon_color("pulse"),
			}, player.position)
		"rail":
			_spawn_player_bullet({
				"kind": "rail",
				"damage": stats.get("damage", 2),
				"radius": stats.get("beam_width", 5.0),
				"velocity": Vector2.ZERO,
				"life_time": 0.09,
				"pierce": 99,
				"beam_length": play_area.size.y * 0.95,
				"color": _weapon_color("rail"),
			}, player.position + Vector2(0.0, -PLAYER_COLLISION_RADIUS))
		_:
			_spawn_player_bullet({
				"kind": "needle",
				"damage": stats.get("damage", 1),
				"radius": 4.6,
				"velocity": Vector2.UP * float(stats.get("speed", 480.0)),
				"life_time": 1.7,
				"pierce": stats.get("pierce", 0),
				"color": _weapon_color("needle"),
			}, player.position + Vector2(0.0, -PLAYER_COLLISION_RADIUS))


## Adds one player projectile to the scene.
func _spawn_player_bullet(settings: Dictionary, spawn_position: Vector2) -> void:
	var bullet = PlayerBulletScript.new()
	bullet.position = spawn_position
	bullet.z_index = 14
	bullet.configure(settings)
	add_child(bullet)
	player_bullets.append(bullet)


## Returns weapon stats for the current type and level.
func _weapon_stats() -> Dictionary:
	match current_weapon:
		"fan":
			return {
				"cooldown": max(0.36, 0.86 - float(weapon_level) * 0.06),
				"damage": 1,
				"shots": 3 + min(weapon_level, 3) * 2,
				"spread_degrees": 20.0 + float(weapon_level) * 4.5,
				"speed": 430.0 + float(weapon_level) * 18.0,
			}
		"pulse":
			return {
				"cooldown": max(0.82, 1.78 - float(weapon_level) * 0.16),
				"damage": 1 + int(float(weapon_level) / 2.0),
				"pulse_radius": 88.0 + float(weapon_level) * 22.0,
				"pulse_speed": 340.0 + float(weapon_level) * 24.0,
			}
		"rail":
			return {
				"cooldown": max(0.48, 1.34 - float(weapon_level) * 0.12),
				"damage": 2 + int(float(weapon_level) / 2.0),
				"beam_width": 4.5 + float(weapon_level) * 1.3,
			}
		_:
			return {
				"cooldown": max(0.18, 0.74 - float(weapon_level) * 0.085),
				"damage": 1 + int(float(weapon_level) / 2.0),
				"speed": 520.0 + float(weapon_level) * 34.0,
				"pierce": 1 if weapon_level >= 3 else 0,
			}


## Returns Orbit weapon stats because it deals contact damage instead of firing.
func _orbit_stats() -> Dictionary:
	return {
		"count": 1 + min(weapon_level, MAX_WEAPON_LEVEL),
		"radius": 38.0 + float(weapon_level) * 7.0,
		"damage": 1 + int(float(weapon_level) / 3.0),
		"hit_interval": max(0.18, 0.42 - float(weapon_level) * 0.03),
		"blade_radius": 8.0,
	}


## Computes current orbit blade positions for drawing and collision.
func _orbit_positions() -> Array:
	var points := []
	var stats := _orbit_stats()
	var count := int(stats.get("count", 1))
	var radius := float(stats.get("radius", 38.0))
	for i in range(count):
		var angle := orbit_angle + TAU * float(i) / float(count)
		points.append(player.position + Vector2(cos(angle), sin(angle)) * radius)
	return points


## Damages the player and ends the run when health reaches zero.
func _damage_player(reason: String) -> void:
	if player == null or game_over:
		return
	if not player.apply_hit():
		return

	_spawn_burst(player.position, Color("#ff5d73"), 40.0, 0.22)
	status_label.text = "DAMAGE  %s" % reason

	if player.hp <= 0:
		_end_game(reason)


## Removes an enemy without awarding score.
func _remove_enemy(enemy) -> void:
	if enemies.has(enemy):
		enemies.erase(enemy)
	if is_instance_valid(enemy):
		enemy.queue_free()


## Awards score, plays feedback, and handles Splitter children.
func _kill_enemy(enemy) -> void:
	if not enemies.has(enemy):
		return

	var death_position: Vector2 = enemy.position
	var enemy_kind: String = enemy.kind
	kill_score += enemy.score_value
	score = int(survival_time * 10.0) + kill_score
	_spawn_burst(death_position, enemy.body_color, 30.0, 0.2)
	_remove_enemy(enemy)

	if enemy_kind == "splitter":
		for offset in [-18.0, 18.0]:
			var shard = EnemyScript.new()
			shard.configure("shard", survival_time / 28.0)
			shard.position = death_position + Vector2(offset, -6.0)
			shard.z_index = 8
			add_child(shard)
			enemies.append(shard)


## Ends the run and records the local high score table.
func _end_game(reason: String) -> void:
	if game_over:
		return

	game_over = true
	status_label.text = "GAME OVER  %s  /  PRESS R" % reason
	_record_score()
	_update_ui()


## Spawns a short visual burst.
func _spawn_burst(effect_position: Vector2, color: Color, radius: float = 30.0, duration: float = 0.24) -> void:
	var burst = BurstEffectScript.new()
	burst.position = effect_position
	burst.z_index = 30
	burst.configure(color, radius, duration)
	add_child(burst)


## Loads the saved top scores from Godot's user data path.
func _load_leaderboard() -> void:
	var config := ConfigFile.new()
	var error := config.load(LEADERBOARD_PATH)
	leaderboard.clear()
	if error != OK:
		return

	var values = config.get_value("scores", "values", [])
	for value in values:
		leaderboard.append(int(value))
	_sort_leaderboard()


## Records the current run once and saves the top score table.
func _record_score() -> void:
	if score_recorded:
		return

	score_recorded = true
	leaderboard.append(score)
	_sort_leaderboard()

	var config := ConfigFile.new()
	config.set_value("scores", "values", leaderboard)
	config.save(LEADERBOARD_PATH)


## Sorts scores descending and trims to the visible leaderboard limit.
func _sort_leaderboard() -> void:
	leaderboard.sort()
	leaderboard.reverse()
	while leaderboard.size() > MAX_LEADERBOARD_ENTRIES:
		leaderboard.pop_back()


## Formats the local top score list for the HUD.
func _leaderboard_text() -> String:
	var lines := ["LOCAL TOP"]
	if leaderboard.is_empty():
		lines.append("--")
	else:
		for i in range(leaderboard.size()):
			lines.append("%d. %d" % [i + 1, leaderboard[i]])
	return "\n".join(lines)


## Returns a display name for each weapon type.
func _weapon_label(weapon_type: String) -> String:
	match weapon_type:
		"fan":
			return "FAN"
		"pulse":
			return "PULSE"
		"rail":
			return "RAIL"
		"orbit":
			return "ORBIT"
		_:
			return "NEEDLE"


## Returns the shared visual color for a weapon type.
func _weapon_color(weapon_type: String) -> Color:
	match weapon_type:
		"fan":
			return Color("#ffcf6d")
		"pulse":
			return Color("#7cffc4")
		"rail":
			return Color("#b892ff")
		"orbit":
			return Color("#ff8fab")
		_:
			return Color("#85d7ff")


## Removes all gameplay actors from the previous run.
func _clear_gameplay_nodes() -> void:
	var tracked := []
	tracked.append_array(enemies)
	tracked.append_array(player_bullets)
	tracked.append_array(enemy_bullets)
	tracked.append_array(pickups)
	if player != null:
		tracked.append(player)

	for node in tracked:
		if is_instance_valid(node):
			node.queue_free()

	enemies.clear()
	player_bullets.clear()
	enemy_bullets.clear()
	pickups.clear()
	player = null


## Returns true for nodes that still exist and are not waiting for deletion.
func _is_live_node(node: Node) -> bool:
	return is_instance_valid(node) and not node.is_queued_for_deletion()


## Returns a compacted copy of an array of scene nodes.
func _compact_node_array(source: Array) -> Array:
	var result := []
	for node in source:
		if _is_live_node(node):
			result.append(node)
	return result


## Checks whether a position has left the play area plus a cleanup margin.
func _outside_play_area(point: Vector2, margin: float) -> bool:
	return not play_area.grow(margin).has_point(point)
