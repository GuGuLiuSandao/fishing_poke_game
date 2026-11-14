extends Control

const OCHRE := Color("#c99a50")
const CRIMSON := Color("#ab4f47")
const IVORY := Color("#dfd3ba")
const TEAL := Color("#4d9c7c")

var amount := 0:
	set(value):
		if amount != value:
			amount = value
			queue_redraw()

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if amount <= 0:
		return
	var factor := minf(size.x / 83.0, size.y / 46.0)
	var center := size / 2.0 + Vector2(0, 7) * factor
	if amount > 1:
		_draw_stack(center + Vector2(-23, 0) * factor, mini(amount, 3), CRIMSON, factor)
	if amount > 3:
		_draw_stack(center + Vector2(23, 1) * factor, mini(amount - 2, 4), TEAL, factor)
	var main_color := OCHRE if amount > 8 else IVORY
	_draw_stack(center, clampi(ceili(sqrt(amount)), 1, 7), main_color, factor)

func _draw_stack(base: Vector2, count: int, color: Color, factor: float) -> void:
	_ellipse(base + Vector2(1, 3) * factor, Vector2(16, 7) * factor, Color(0, 0, 0, 0.35))
	var radius := Vector2(14, 7) * factor
	for layer in range(count):
		var position := base - Vector2(0, 3 * layer) * factor
		_ellipse(position + Vector2(0, 3) * factor, radius, color.darkened(0.47))
		for offset in [-9.0, 0.0, 9.0]:
			draw_line(position + Vector2(offset, 6) * factor, position + Vector2(offset, 9) * factor, IVORY.darkened(0.15), maxf(1.0, factor * 1.4), true)
		_ellipse(position, radius, color.lightened(0.12))
	_ellipse(base - Vector2(0, 3 * (count - 1)) * factor, radius * 0.58, color.darkened(0.30))
	_ellipse(base - Vector2(0, 3 * (count - 1)) * factor, radius * 0.43, color)

func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for segment in range(24):
		var direction := Vector2.from_angle(TAU * segment / 24.0)
		points.append(center + direction * radius)
	draw_colored_polygon(points, color)
