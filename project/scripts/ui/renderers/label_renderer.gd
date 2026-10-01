class_name LabelRenderer
extends RefCounted

## LabelRenderer: Renders Ground reference (0) and NetLabels (+5V, -5V, VCC, signal flags).

const COLOR_TEXT = Color(0.8, 0.85, 0.9, 1.0)
const COLOR_TEXT_VALUE = Color(0.4, 0.85, 0.5, 1.0)

static func draw_ground(canvas: CanvasItem, tf: Callable, color: Color) -> void:
	var line_width = 2.5
	canvas.draw_line(tf.call(Vector2(0, -20)), tf.call(Vector2(0, 0)), color, line_width)
	canvas.draw_line(tf.call(Vector2(-16, 0)), tf.call(Vector2(16, 0)), color, line_width)
	canvas.draw_line(tf.call(Vector2(-10, 6)), tf.call(Vector2(10, 6)), color, line_width)
	canvas.draw_line(tf.call(Vector2(-4, 12)), tf.call(Vector2(4, 12)), color, line_width)

static func draw_net_label(canvas: CanvasItem, tf: Callable, comp: CircuitComponent, color: Color, font: Font) -> void:
	var line_width = 2.5
	var lbl = comp.value.strip_edges()
	var u_lbl = lbl.to_upper()
	var used_font = font if font else ThemeDB.fallback_font

	if u_lbl == "0" or u_lbl == "GND":
		draw_ground(canvas, tf, color)
		return

	if lbl.begins_with("+") or u_lbl.begins_with("VCC") or u_lbl.begins_with("VDD"):
		# Positive power rail: upward bar/arrow with label above
		var p_base = tf.call(Vector2.ZERO)
		var p_top = tf.call(Vector2(0, -14))
		canvas.draw_line(p_base, p_top, color, line_width)
		var tri = [tf.call(Vector2(-7, -14)), tf.call(Vector2(0, -22)), tf.call(Vector2(7, -14))]
		canvas.draw_colored_polygon(PackedVector2Array(tri), color)
		if used_font:
			var txt_size = used_font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			var text_pos = tf.call(Vector2(-txt_size.x / 2.0, -26))
			canvas.draw_string(used_font, text_pos, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_TEXT_VALUE)
	elif lbl.begins_with("-") or u_lbl.begins_with("VEE") or u_lbl.begins_with("VSS"):
		# Negative power rail: downward arrow with label below
		var p_base = tf.call(Vector2.ZERO)
		var p_bot = tf.call(Vector2(0, 14))
		canvas.draw_line(p_base, p_bot, color, line_width)
		var tri = [tf.call(Vector2(-7, 14)), tf.call(Vector2(0, 22)), tf.call(Vector2(7, 14))]
		canvas.draw_colored_polygon(PackedVector2Array(tri), color)
		if used_font:
			var txt_size = used_font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			var text_pos = tf.call(Vector2(-txt_size.x / 2.0, 35))
			canvas.draw_string(used_font, text_pos, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_TEXT_VALUE)
	else:
		# Signal banner/flag
		var p_base = tf.call(Vector2.ZERO)
		var p_stem = tf.call(Vector2(12, 0))
		canvas.draw_line(p_base, p_stem, color, line_width)
		var w = max(36.0, used_font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0) if used_font else 40.0
		var poly = [
			tf.call(Vector2(12, -10)),
			tf.call(Vector2(12 + w, -10)),
			tf.call(Vector2(12 + w + 8, 0)),
			tf.call(Vector2(12 + w, 10)),
			tf.call(Vector2(12, 10))
		]
		canvas.draw_colored_polygon(PackedVector2Array(poly), Color(0.12, 0.22, 0.35, 0.9))
		for i in range(poly.size()):
			canvas.draw_line(poly[i], poly[(i + 1) % poly.size()], color, 1.5)
		if used_font:
			var text_pos = tf.call(Vector2(18, 4))
			canvas.draw_string(used_font, text_pos, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT)

static func draw_junction(canvas: CanvasItem, pos: Vector2, color: Color) -> void:
	# Standard EDA solder dot
	canvas.draw_circle(pos, 4.0, color)

