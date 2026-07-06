## Short-lived visual effect for kills and weapon impacts.
##
## This effect is feedback-only; it does not change score or collisions.
extends Node2D
class_name BurstEffect

var effect_color := Color("#f8f5d8")
var max_radius := 32.0
var life_time := 0.26
var age := 0.0


## Sets visual parameters for this burst instance.
func configure(color: Color, radius: float = 32.0, duration: float = 0.26) -> void:
	effect_color = color
	max_radius = radius
	life_time = duration
	queue_redraw()


## Expands and fades until the effect deletes itself.
func _process(delta: float) -> void:
	age += delta
	if age >= life_time:
		queue_free()
	queue_redraw()


## Draws a fading ring and small center flash.
func _draw() -> void:
	var ratio := clampf(age / max(life_time, 0.01), 0.0, 1.0)
	var color := effect_color
	color.a = 1.0 - ratio
	draw_arc(Vector2.ZERO, max_radius * ratio, 0.0, TAU, 48, color, 3.0, true)
	color.a *= 0.24
	draw_circle(Vector2.ZERO, max_radius * ratio, color)
