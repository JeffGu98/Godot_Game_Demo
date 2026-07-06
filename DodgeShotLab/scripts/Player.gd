## Player ship for Dodge Shot Lab.
##
## The player only owns movement, health, invulnerability, and ship drawing.
## Weapon logic stays in Main so auto-fire rules can be tuned in one place.
extends Node2D
class_name DodgePlayer

# Player tuning. Movement must be responsive because this is the only input.
const MAX_HP := 3
const MOVE_SPEED := 330.0
const COLLISION_RADIUS := 14.0
const HIT_INVULNERABLE_TIME := 1.0

var hp := MAX_HP
var invulnerable_time := 0.0
var play_area := Rect2()


## Resets health, position, and bounds at the start of a run.
func reset(spawn_position: Vector2, bounds: Rect2) -> void:
	hp = MAX_HP
	invulnerable_time = 0.0
	play_area = bounds
	position = spawn_position
	queue_redraw()


## Handles frame-based invulnerability countdown and redraws blink feedback.
func _process(delta: float) -> void:
	if invulnerable_time > 0.0:
		invulnerable_time = max(0.0, invulnerable_time - delta)
		queue_redraw()


## Moves from keyboard state and clamps the ship inside the playable area.
func move_from_input(delta: float) -> void:
	var direction := _read_move_vector()
	position += direction * MOVE_SPEED * delta
	position.x = clampf(position.x, play_area.position.x + COLLISION_RADIUS, play_area.end.x - COLLISION_RADIUS)
	position.y = clampf(position.y, play_area.position.y + COLLISION_RADIUS, play_area.end.y - COLLISION_RADIUS)


## Applies one point of damage if the ship is not currently invulnerable.
func apply_hit() -> bool:
	if invulnerable_time > 0.0:
		return false

	hp -= 1
	invulnerable_time = HIT_INVULNERABLE_TIME
	queue_redraw()
	return true


## Returns true while collision damage should be ignored.
func is_invulnerable() -> bool:
	return invulnerable_time > 0.0


## Draws a compact ship silhouette with blink feedback after damage.
func _draw() -> void:
	var alpha := 1.0
	if invulnerable_time > 0.0 and int(invulnerable_time * 12.0) % 2 == 0:
		alpha = 0.34

	var body_color := Color("#74e2ff")
	body_color.a = alpha
	var core_color := Color("#f8f5d8")
	core_color.a = alpha
	var shadow_color := Color("#1d5a73")
	shadow_color.a = alpha

	var hull := PackedVector2Array([
		Vector2(0.0, -19.0),
		Vector2(15.0, 15.0),
		Vector2(0.0, 8.0),
		Vector2(-15.0, 15.0),
	])
	draw_colored_polygon(hull, body_color)
	draw_polyline(hull, shadow_color, 2.0, true)
	draw_circle(Vector2.ZERO, 5.0, core_color)


## Reads WASD and arrow keys without requiring an InputMap setup.
func _read_move_vector() -> Vector2:
	var direction := Vector2.ZERO

	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		direction.y += 1.0

	if direction.length_squared() > 1.0:
		return direction.normalized()
	return direction
