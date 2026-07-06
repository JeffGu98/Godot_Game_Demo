## Enemy projectile used by Spitter enemies.
##
## The bullet is intentionally simple and readable: a single circle moving in a
## fixed direction, so deaths can be understood from position and spacing.
extends Node2D
class_name EnemyBullet

var radius := 6.0
var velocity := Vector2.ZERO
var life_time := 4.0
var age := 0.0


## Sets direction and speed at spawn time.
func configure(spawn_velocity: Vector2, bullet_radius: float = 6.0) -> void:
	velocity = spawn_velocity
	radius = bullet_radius
	queue_redraw()


## Moves until the bullet expires.
func _process(delta: float) -> void:
	age += delta
	position += velocity * delta
	if age >= life_time:
		queue_free()


## Draws a high-contrast enemy bullet.
func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color("#ff5d73"))
	draw_circle(Vector2.ZERO, radius * 0.45, Color("#ffd1dc"))
