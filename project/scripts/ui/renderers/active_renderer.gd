class_name ActiveRenderer
extends RefCounted

## ActiveRenderer: Renders sources, diodes, transistors, and op-amps.

static func draw_voltage_source(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	var radius = 22.0
	var center = tf.call(Vector2.ZERO)

	# Leads: pos at (0, -40), neg at (0, 40)
	canvas.draw_line(tf.call(Vector2(0, -40)), tf.call(Vector2(0, -radius)), color, line_width)
	canvas.draw_line(tf.call(Vector2(0, radius)), tf.call(Vector2(0, 40)), color, line_width)
	canvas.draw_arc(center, radius, 0, TAU, 32, color, line_width)

	# '+' sign near pos terminal
	var p_pos = tf.call(Vector2(0, -11))
	canvas.draw_line(p_pos + Vector2(-5, 0), p_pos + Vector2(5, 0), color, 2.0)
	canvas.draw_line(p_pos + Vector2(0, -5), p_pos + Vector2(0, 5), color, 2.0)

	# '-' sign near neg terminal
	var p_neg = tf.call(Vector2(0, 11))
	canvas.draw_line(p_neg + Vector2(-5, 0), p_neg + Vector2(5, 0), color, 2.0)

static func draw_current_source(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	var radius = 22.0
	var center = tf.call(Vector2.ZERO)

	canvas.draw_line(tf.call(Vector2(0, -40)), tf.call(Vector2(0, -radius)), color, line_width)
	canvas.draw_line(tf.call(Vector2(0, radius)), tf.call(Vector2(0, 40)), color, line_width)
	canvas.draw_arc(center, radius, 0, TAU, 32, color, line_width)

	# Arrow inside pointing from neg to pos (upward)
	var arrow_start = tf.call(Vector2(0, 12))
	var arrow_tip = tf.call(Vector2(0, -12))
	canvas.draw_line(arrow_start, arrow_tip, color, 2.0)
	canvas.draw_line(arrow_tip, tf.call(Vector2(-5, -5)), color, 2.0)
	canvas.draw_line(arrow_tip, tf.call(Vector2(5, -5)), color, 2.0)

static func draw_diode(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	canvas.draw_line(tf.call(Vector2(-35, 0)), tf.call(Vector2(-14, 0)), color, line_width)
	canvas.draw_line(tf.call(Vector2(14, 0)), tf.call(Vector2(35, 0)), color, line_width)
	var tri = [tf.call(Vector2(-14, -14)), tf.call(Vector2(14, 0)), tf.call(Vector2(-14, 14))]
	canvas.draw_line(tri[0], tri[1], color, line_width)
	canvas.draw_line(tri[1], tri[2], color, line_width)
	canvas.draw_line(tri[2], tri[0], color, line_width)
	canvas.draw_line(tf.call(Vector2(14, -14)), tf.call(Vector2(14, 14)), color, line_width)

static func draw_bjt_npn(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	canvas.draw_line(tf.call(Vector2(-35, 0)), tf.call(Vector2(-12, 0)), color, line_width)
	canvas.draw_line(tf.call(Vector2(-12, -22)), tf.call(Vector2(-12, 22)), color, 3.5)
	canvas.draw_line(tf.call(Vector2(-12, -10)), tf.call(Vector2(14, -24)), color, line_width)
	canvas.draw_line(tf.call(Vector2(14, -24)), tf.call(Vector2(20, -35)), color, line_width)
	var e_mid = tf.call(Vector2(14, 24))
	canvas.draw_line(tf.call(Vector2(-12, 10)), e_mid, color, line_width)
	canvas.draw_line(e_mid, tf.call(Vector2(20, 35)), color, line_width)
	canvas.draw_line(e_mid, e_mid + (tf.call(Vector2(14, 24)) - tf.call(Vector2(0, 16))).normalized().rotated(0.5) * -8.0, color, 2.0)

static func draw_bjt_pnp(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	canvas.draw_line(tf.call(Vector2(-35, 0)), tf.call(Vector2(-12, 0)), color, line_width)
	canvas.draw_line(tf.call(Vector2(-12, -22)), tf.call(Vector2(-12, 22)), color, 3.5)
	canvas.draw_line(tf.call(Vector2(-12, -10)), tf.call(Vector2(14, -24)), color, line_width)
	canvas.draw_line(tf.call(Vector2(14, -24)), tf.call(Vector2(20, -35)), color, line_width)
	canvas.draw_line(tf.call(Vector2(-12, 10)), tf.call(Vector2(14, 24)), color, line_width)
	canvas.draw_line(tf.call(Vector2(14, 24)), tf.call(Vector2(20, 35)), color, line_width)

static func draw_opamp(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	var p_top = tf.call(Vector2(-30, -30))
	var p_out = tf.call(Vector2(30, 0))
	var p_bot = tf.call(Vector2(-30, 30))
	canvas.draw_line(p_top, p_out, color, line_width)
	canvas.draw_line(p_out, p_bot, color, line_width)
	canvas.draw_line(p_bot, p_top, color, line_width)
	canvas.draw_line(tf.call(Vector2(-40, -18)), tf.call(Vector2(-30, -18)), color, line_width)
	canvas.draw_line(tf.call(Vector2(-40, 18)), tf.call(Vector2(-30, 18)), color, line_width)
	canvas.draw_line(tf.call(Vector2(30, 0)), tf.call(Vector2(40, 0)), color, line_width)
	canvas.draw_line(tf.call(Vector2(-24, -18)), tf.call(Vector2(-18, -18)), color, 1.8)
	canvas.draw_line(tf.call(Vector2(-24, 18)), tf.call(Vector2(-18, 18)), color, 1.8)
	canvas.draw_line(tf.call(Vector2(-21, 15)), tf.call(Vector2(-21, 21)), color, 1.8)
