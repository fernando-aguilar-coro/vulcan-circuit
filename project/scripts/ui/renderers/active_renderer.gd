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

static func draw_transformer(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	# Primary terminal leads
	canvas.draw_line(tf.call(Vector2(-40, -20)), tf.call(Vector2(-12, -20)), color, line_width)
	canvas.draw_line(tf.call(Vector2(-40, 20)), tf.call(Vector2(-12, 20)), color, line_width)
	# Primary coil (3 arcs facing left)
	for i in range(3):
		var cy = -13.3 + i * 13.3
		canvas.draw_arc(tf.call(Vector2(-12, cy)), 6.7, -PI * 0.5, PI * 0.5, 16, color, line_width)

	# Secondary terminal leads
	canvas.draw_line(tf.call(Vector2(40, -20)), tf.call(Vector2(12, -20)), color, line_width)
	canvas.draw_line(tf.call(Vector2(40, 20)), tf.call(Vector2(12, 20)), color, line_width)
	# Secondary coil (3 arcs facing right)
	for i in range(3):
		var cy = -13.3 + i * 13.3
		canvas.draw_arc(tf.call(Vector2(12, cy)), 6.7, PI * 0.5, PI * 1.5, 16, color, line_width)

	# Core (two parallel vertical lines in the middle)
	canvas.draw_line(tf.call(Vector2(-3, -24)), tf.call(Vector2(-3, 24)), color, 1.8)
	canvas.draw_line(tf.call(Vector2(3, -24)), tf.call(Vector2(3, 24)), color, 1.8)

static func draw_scr(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	# Anode (0, -40) to (0, -14), Cathode (0, 14) to (0, 40)
	canvas.draw_line(tf.call(Vector2(0, -40)), tf.call(Vector2(0, -14)), color, line_width)
	canvas.draw_line(tf.call(Vector2(0, 14)), tf.call(Vector2(0, 40)), color, line_width)

	# Triangle pointing down towards cathode
	var tri = [tf.call(Vector2(-14, -14)), tf.call(Vector2(14, -14)), tf.call(Vector2(0, 14))]
	canvas.draw_line(tri[0], tri[1], color, line_width)
	canvas.draw_line(tri[1], tri[2], color, line_width)
	canvas.draw_line(tri[2], tri[0], color, line_width)

	# Cathode bar
	canvas.draw_line(tf.call(Vector2(-14, 14)), tf.call(Vector2(14, 14)), color, line_width)

	# Gate terminal at (-40, 20) connecting to cathode at (-10, 14)
	canvas.draw_line(tf.call(Vector2(-40, 20)), tf.call(Vector2(-20, 20)), color, line_width)
	canvas.draw_line(tf.call(Vector2(-20, 20)), tf.call(Vector2(-10, 14)), color, line_width)

static func draw_triac(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	# Main terminals: MT2 (0, -40) to (0, -14), MT1 (0, 14) to (0, 40)
	canvas.draw_line(tf.call(Vector2(0, -40)), tf.call(Vector2(0, -14)), color, line_width)
	canvas.draw_line(tf.call(Vector2(0, 14)), tf.call(Vector2(0, 40)), color, line_width)

	# First triangle pointing down
	var tri1 = [tf.call(Vector2(-12, -14)), tf.call(Vector2(6, -14)), tf.call(Vector2(-3, 14))]
	canvas.draw_line(tri1[0], tri1[1], color, line_width)
	canvas.draw_line(tri1[1], tri1[2], color, line_width)
	canvas.draw_line(tri1[2], tri1[0], color, line_width)

	# Second inverse triangle pointing up
	var tri2 = [tf.call(Vector2(12, 14)), tf.call(Vector2(-6, 14)), tf.call(Vector2(3, -14))]
	canvas.draw_line(tri2[0], tri2[1], color, line_width)
	canvas.draw_line(tri2[1], tri2[2], color, line_width)
	canvas.draw_line(tri2[2], tri2[0], color, line_width)

	# Gate terminal at (-40, 20)
	canvas.draw_line(tf.call(Vector2(-40, 20)), tf.call(Vector2(-18, 20)), color, line_width)
	canvas.draw_line(tf.call(Vector2(-18, 20)), tf.call(Vector2(-8, 14)), color, line_width)

static func draw_ic(canvas: CanvasItem, tf: Callable, comp: CircuitComponent, color: Color, font: Font) -> void:
	var line_width = 2.0
	var w = comp.ic_box_size.x
	var h = comp.ic_box_size.y
	var half_w = w / 2.0
	var half_h = h / 2.0

	# IC body rectangle
	var corners = [
		tf.call(Vector2(-half_w, -half_h)),
		tf.call(Vector2(half_w, -half_h)),
		tf.call(Vector2(half_w, half_h)),
		tf.call(Vector2(-half_w, half_h))
	]
	var fill_colors = PackedColorArray([Color(0.1, 0.13, 0.18, 0.9), Color(0.1, 0.13, 0.18, 0.9), Color(0.1, 0.13, 0.18, 0.9), Color(0.1, 0.13, 0.18, 0.9)])
	canvas.draw_polygon(PackedVector2Array(corners), fill_colors)

	for i in range(4):
		canvas.draw_line(corners[i], corners[(i + 1) % 4], color, line_width)

	# Orientation Notch on top edge
	var notch_c = tf.call(Vector2(0, -half_h))
	canvas.draw_arc(notch_c, 5.0, 0, PI, 12, color, 1.8)

	# Pin leads and pin name text
	var used_font = font if font else ThemeDB.fallback_font
	for pin in comp.pins:
		var p_local = pin.local_position
		var p_edge = Vector2.ZERO
		if p_local.x < -half_w:
			p_edge = Vector2(-half_w, p_local.y)
		elif p_local.x > half_w:
			p_edge = Vector2(half_w, p_local.y)
		elif p_local.y > half_h:
			p_edge = Vector2(p_local.x, half_h)
		elif p_local.y < -half_h:
			p_edge = Vector2(p_local.x, -half_h)

		canvas.draw_line(tf.call(p_edge), tf.call(p_local), color, line_width)

		var text_offset = Vector2.ZERO
		if p_local.x < -half_w:
			text_offset = Vector2(4, 3)
		elif p_local.x > half_w:
			text_offset = Vector2(-16, 3)
		elif p_local.y > half_h:
			text_offset = Vector2(-8, -4)
		else:
			text_offset = Vector2(-8, 12)
		canvas.draw_string(used_font, tf.call(p_edge + text_offset), pin.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.8, 0.9, 0.8))

	# Chip model / name in center of IC
	var model_str = comp.ic_data.get("model", comp.value)
	var str_size = used_font.get_string_size(model_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
	canvas.draw_string(used_font, tf.call(Vector2(-str_size.x / 2.0, str_size.y / 4.0)), model_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0.3, 0.9, 0.95, 1.0))

