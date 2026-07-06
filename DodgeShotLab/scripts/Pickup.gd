## Weapon package pickup.
##
## A pickup either upgrades the current bullet type or switches to a new bullet
## type at level 0. It drifts downward to create movement decisions.
extends Node2D
class_name WeaponPickup

var weapon_type := "needle"
var radius := 16.0
var fall_speed := 42.0
var package_color := Color("#f8f5d8")


## Configures the package type and color when spawned.
func configure(next_weapon_type: String, color: Color) -> void:
	weapon_type = next_weapon_type
	package_color = color
	queue_redraw()


## Drifts downward until Main removes it outside the play area.
func _process(delta: float) -> void:
	position.y += fall_speed * delta


## Draws a square package with a small weapon-specific symbol.
func _draw() -> void:
	var rect := Rect2(Vector2(-radius, -radius), Vector2(radius * 2.0, radius * 2.0))
	draw_rect(rect, package_color, true)
	draw_rect(rect, Color("#111923"), false, 2.0)

	match weapon_type:
		"needle":
			draw_line(Vector2(0.0, radius * 0.62), Vector2(0.0, -radius * 0.62), Color("#111923"), 3.0, true)
		"fan":
			draw_line(Vector2.ZERO, Vector2(-radius * 0.58, -radius * 0.5), Color("#111923"), 2.5, true)
			draw_line(Vector2.ZERO, Vector2(0.0, -radius * 0.68), Color("#111923"), 2.5, true)
			draw_line(Vector2.ZERO, Vector2(radius * 0.58, -radius * 0.5), Color("#111923"), 2.5, true)
		"pulse":
			draw_arc(Vector2.ZERO, radius * 0.52, 0.0, TAU, 28, Color("#111923"), 3.0, true)
		"rail":
			draw_rect(Rect2(Vector2(-3.0, -radius * 0.64), Vector2(6.0, radius * 1.28)), Color("#111923"), true)
		"orbit":
			draw_circle(Vector2.ZERO, 3.5, Color("#111923"))
			draw_arc(Vector2.ZERO, radius * 0.55, 0.0, TAU, 32, Color("#111923"), 2.5, true)
