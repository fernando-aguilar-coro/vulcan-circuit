class_name ComponentRenderer
extends RefCounted

## ComponentRenderer: Orchestrates rendering across passive, active, and label renderers.

const COLOR_NORMAL = Color(0.9, 0.92, 0.95, 1.0)
const COLOR_SELECTED = Color(0.2, 0.75, 1.0, 1.0)
const COLOR_PIN = Color(0.95, 0.6, 0.1, 1.0)
const COLOR_PIN_HOVER = Color(0.2, 1.0, 0.4, 1.0)
const COLOR_PIN_BORDER = Color(0.1, 0.12, 0.15, 1.0)
const COLOR_TEXT = Color(0.8, 0.85, 0.9, 1.0)
const COLOR_TEXT_VALUE = Color(0.4, 0.85, 0.5, 1.0)

static func draw_component(canvas: CanvasItem, comp: CircuitComponent, is_selected: bool, hovered_pin_id: String, font: Font) -> void:
	if comp.is_virtual:
		return

	var color = COLOR_SELECTED if is_selected else COLOR_NORMAL
	var rot_rad = deg_to_rad(comp.rotation_deg)
	var tf = func(local: Vector2) -> Vector2:
		return comp.position + local.rotated(rot_rad)

	# Selection highlight
	if is_selected and comp.type != CircuitComponent.Type.JUNCTION:
		var bounds_size = Vector2(90, 60) if comp.type == CircuitComponent.Type.RESISTOR else Vector2(70, 90)
		var sel_rect = Rect2(comp.position - bounds_size / 2.0, bounds_size)
		canvas.draw_rect(sel_rect, Color(0.2, 0.65, 1.0, 0.12), true)
		canvas.draw_rect(sel_rect, Color(0.2, 0.65, 1.0, 0.7), false, 1.5)

	# Dispatch to specialized renderers
	match comp.type:
		CircuitComponent.Type.RESISTOR:
			PassiveRenderer.draw_resistor(canvas, tf, color)
		CircuitComponent.Type.CAPACITOR:
			PassiveRenderer.draw_capacitor(canvas, tf, color)
		CircuitComponent.Type.INDUCTOR:
			PassiveRenderer.draw_inductor(canvas, tf, color)
		CircuitComponent.Type.VOLTAGE_SOURCE:
			ActiveRenderer.draw_voltage_source(canvas, tf, color)
		CircuitComponent.Type.CURRENT_SOURCE:
			ActiveRenderer.draw_current_source(canvas, tf, color)
		CircuitComponent.Type.DIODE:
			ActiveRenderer.draw_diode(canvas, tf, color)
		CircuitComponent.Type.BJT_NPN:
			ActiveRenderer.draw_bjt_npn(canvas, tf, color)
		CircuitComponent.Type.BJT_PNP:
			ActiveRenderer.draw_bjt_pnp(canvas, tf, color)
		CircuitComponent.Type.OPAMP:
			ActiveRenderer.draw_opamp(canvas, tf, color)
		CircuitComponent.Type.GROUND:
			LabelRenderer.draw_ground(canvas, tf, color)
		CircuitComponent.Type.NET_LABEL:
			LabelRenderer.draw_net_label(canvas, tf, comp, color, font)
		CircuitComponent.Type.JUNCTION:
			LabelRenderer.draw_junction(canvas, comp.position, color)

	# Draw terminal pins (skip for junction)
	if comp.type != CircuitComponent.Type.JUNCTION:
		for pin in comp.pins:
			var p_world = pin.get_world_position(comp.position, comp.rotation_deg)
			var is_hovered = (pin.id == hovered_pin_id)
			var pin_color = COLOR_PIN_HOVER if is_hovered else COLOR_PIN
			var pin_radius = 5.5 if is_hovered else 4.0
			canvas.draw_circle(p_world, pin_radius + 1.5, COLOR_PIN_BORDER)
			canvas.draw_circle(p_world, pin_radius, pin_color)

	# Draw ID and Value labels (skip for ground and netlabels)
	_draw_labels(canvas, comp, font)

static func _draw_labels(canvas: CanvasItem, comp: CircuitComponent, font: Font) -> void:
	if comp.type == CircuitComponent.Type.GROUND or comp.type == CircuitComponent.Type.NET_LABEL or comp.type == CircuitComponent.Type.JUNCTION:
		return
	var offset_id = Vector2(-25, -28)
	var offset_val = Vector2(-25, 34)
	if comp.rotation_deg == 90 or comp.rotation_deg == 270:
		offset_id = Vector2(28, -8)
		offset_val = Vector2(28, 12)

	var used_font = font if font else ThemeDB.fallback_font
	canvas.draw_string(used_font, comp.position + offset_id, comp.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_TEXT)
	canvas.draw_string(used_font, comp.position + offset_val, comp.value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_TEXT_VALUE)
