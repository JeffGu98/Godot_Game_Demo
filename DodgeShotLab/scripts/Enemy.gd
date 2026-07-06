## Enemy actor for the dodge shooter prototype.
##
## Each enemy type owns its health, movement profile, score value, and optional
## firing timer. Main decides spawning and collision outcomes.
extends Node2D
class_name DodgeEnemy

var kind := "wisp"
var max_hp := 2
var hp := 2
var speed := 80.0
var radius := 16.0
var score_value := 20
var shoot_interval := 0.0
var shoot_speed := 160.0
var body_color := Color("#ffcf6d")
var rim_color := Color("#5c355e")

var age := 0.0
var shoot_timer := 0.0
var hit_flash := 0.0


## Applies type stats and light threat scaling when the enemy is spawned.
func configure(enemy_kind: String, threat: float = 0.0) -> void:
	kind = enemy_kind
	age = 0.0
	hit_flash = 0.0

	match kind:
		"charger":
			max_hp = 1
			speed = 176.0 + threat * 5.0
			radius = 13.0
			score_value = 18
			shoot_interval = 0.0
			body_color = Color("#ff7b72")
			rim_color = Color("#5f1f34")
		"bulwark":
			max_hp = 8 + int(threat * 0.6)
			speed = 46.0 + threat * 2.0
			radius = 25.0
			score_value = 70
			shoot_interval = 0.0
			body_color = Color("#b892ff")
			rim_color = Color("#38265e")
		"spitter":
			max_hp = 4 + int(threat * 0.4)
			speed = 68.0 + threat * 2.4
			radius = 18.0
			score_value = 45
			shoot_interval = max(0.85, 1.55 - threat * 0.05)
			shoot_speed = 178.0 + threat * 4.0
			body_color = Color("#83e377")
			rim_color = Color("#1f5f3f")
		"splitter":
			max_hp = 3 + int(threat * 0.25)
			speed = 92.0 + threat * 2.6
			radius = 17.0
			score_value = 38
			shoot_interval = 0.0
			body_color = Color("#ffd166")
			rim_color = Color("#7a4c1e")
		"shard":
			max_hp = 1
			speed = 146.0 + threat * 4.0
			radius = 10.0
			score_value = 10
			shoot_interval = 0.0
			body_color = Color("#ffb3c1")
			rim_color = Color("#7c2745")
		_:
			max_hp = 2 + int(threat * 0.25)
			speed = 84.0 + threat * 2.2
			radius = 16.0
			score_value = 22
			shoot_interval = 0.0
			body_color = Color("#ffcf6d")
			rim_color = Color("#5c355e")

	hp = max_hp
	shoot_timer = shoot_interval * 0.65
	queue_redraw()


## Advances the enemy toward pressure positions near the player.
func advance(delta: float, player_position: Vector2) -> void:
	age += delta
	if hit_flash > 0.0:
		hit_flash = max(0.0, hit_flash - delta)

	var horizontal := 0.0
	match kind:
		"charger":
			horizontal = clampf((player_position.x - position.x) * 1.8, -speed * 0.9, speed * 0.9)
		"spitter":
			horizontal = sin(age * 2.0) * speed * 0.38
		"wisp":
			horizontal = sin(age * 2.8 + position.x * 0.02) * speed * 0.35
		"shard":
			horizontal = clampf((player_position.x - position.x) * 1.2, -speed * 0.75, speed * 0.75)
		_:
			horizontal = sin(age * 1.4) * speed * 0.16

	position += Vector2(horizontal, speed) * delta
	queue_redraw()


## Returns true when this enemy should emit an enemy bullet this frame.
func should_fire(delta: float) -> bool:
	if shoot_interval <= 0.0:
		return false

	shoot_timer -= delta
	if shoot_timer > 0.0:
		return false

	shoot_timer = shoot_interval
	return true


## Applies weapon damage and reports whether the enemy died.
func take_damage(amount: int) -> bool:
	hp -= amount
	hit_flash = 0.07
	queue_redraw()
	return hp <= 0


## Draws each enemy as a readable shape with a small health bar.
func _draw() -> void:
	var fill := Color("#ffffff") if hit_flash > 0.0 else body_color
	draw_circle(Vector2.ZERO, radius, fill)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, rim_color, 2.0, true)

	match kind:
		"charger":
			draw_line(Vector2(-6.0, -4.0), Vector2(7.0, 5.0), rim_color, 3.0, true)
			draw_line(Vector2(6.0, -4.0), Vector2(-7.0, 5.0), rim_color, 3.0, true)
		"bulwark":
			draw_rect(Rect2(Vector2(-radius * 0.52, -radius * 0.24), Vector2(radius * 1.04, radius * 0.48)), rim_color, true)
		"spitter":
			draw_circle(Vector2.ZERO, radius * 0.38, rim_color)
		"splitter":
			draw_line(Vector2(-radius * 0.48, 0.0), Vector2(radius * 0.48, 0.0), rim_color, 2.0, true)
			draw_line(Vector2(0.0, -radius * 0.48), Vector2(0.0, radius * 0.48), rim_color, 2.0, true)
		"shard":
			draw_circle(Vector2.ZERO, radius * 0.42, rim_color)

	if hp < max_hp:
		var bar_width := radius * 1.55
		var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
		draw_rect(Rect2(Vector2(-bar_width * 0.5, -radius - 8.0), Vector2(bar_width, 3.0)), Color("#231923"), true)
		draw_rect(Rect2(Vector2(-bar_width * 0.5, -radius - 8.0), Vector2(bar_width * ratio, 3.0)), Color("#f8f5d8"), true)
