class_name PassiveRenderer
extends RefCounted

## PassiveRenderer: Renders passive 2-terminal components (Resistors, Capacitors, Inductors).

static func draw_resistor(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	# Terminal leads
	canvas.draw_line(tf.call(Vector2(-40, 0)), tf.call(Vector2(-24, 0)), color, line_width)
	canvas.draw_line(tf.call(Vector2(24, 0)), tf.call(Vector2(40, 0)), color, line_width)

	# Zigzag body (3 peaks, 3 valleys)
	var pts = [
		tf.call(Vector2(-24, 0)),
		tf.call(Vector2(-20, -12)),
		tf.call(Vector2(-12, 12)),
		tf.call(Vector2(-4, -12)),
		tf.call(Vector2(4, 12)),
		tf.call(Vector2(12, -12)),
		tf.call(Vector2(20, 12)),
		tf.call(Vector2(24, 0))
	]
	for i in range(pts.size() - 1):
		canvas.draw_line(pts[i], pts[i + 1], color, line_width)

static func draw_capacitor(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	canvas.draw_line(tf.call(Vector2(-35, 0)), tf.call(Vector2(-8, 0)), color, line_width)
	canvas.draw_line(tf.call(Vector2(8, 0)), tf.call(Vector2(35, 0)), color, line_width)
	canvas.draw_line(tf.call(Vector2(-8, -18)), tf.call(Vector2(-8, 18)), color, line_width)
	canvas.draw_line(tf.call(Vector2(8, -18)), tf.call(Vector2(8, 18)), color, line_width)

static func draw_inductor(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	canvas.draw_line(tf.call(Vector2(-35, 0)), tf.call(Vector2(-24, 0)), color, line_width)
	canvas.draw_line(tf.call(Vector2(24, 0)), tf.call(Vector2(35, 0)), color, line_width)
	for i in range(3):
		var cx = -16.0 + i * 16.0
		canvas.draw_arc(tf.call(Vector2(cx, 0)), 8.0, PI, TAU, 16, color, line_width)

static func draw_potentiometer(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	# Terminal leads for t1 (-40, 0) and t2 (40, 0)
	canvas.draw_line(tf.call(Vector2(-40, 0)), tf.call(Vector2(-24, 0)), color, line_width)
	canvas.draw_line(tf.call(Vector2(24, 0)), tf.call(Vector2(40, 0)), color, line_width)

	# Zigzag body
	var pts = [
		tf.call(Vector2(-24, 0)),
		tf.call(Vector2(-20, -12)),
		tf.call(Vector2(-12, 12)),
		tf.call(Vector2(-4, -12)),
		tf.call(Vector2(4, 12)),
		tf.call(Vector2(12, -12)),
		tf.call(Vector2(20, 12)),
		tf.call(Vector2(24, 0))
	]
	for i in range(pts.size() - 1):
		canvas.draw_line(pts[i], pts[i + 1], color, line_width)

	# Wiper lead at (0, 40) pointing up with arrow head
	var p_wiper_start = tf.call(Vector2(0, 40))
	var p_wiper_shaft = tf.call(Vector2(0, 18))
	var p_wiper_tip = tf.call(Vector2(0, 6))
	canvas.draw_line(p_wiper_start, p_wiper_shaft, color, line_width)
	canvas.draw_line(p_wiper_shaft, p_wiper_tip, color, line_width)
	# Arrow wings
	canvas.draw_line(p_wiper_tip, tf.call(Vector2(-5, 14)), color, 2.0)
	canvas.draw_line(p_wiper_tip, tf.call(Vector2(5, 14)), color, 2.0)

