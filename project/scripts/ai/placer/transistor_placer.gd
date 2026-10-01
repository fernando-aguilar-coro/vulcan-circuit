class_name TransistorPlacer
extends RefCounted

## TransistorPlacer: Positions 3-terminal active devices (BJT NPN/PNP) on the schematic grid.

const GRID_SNAP: float = 20.0

static func place_transistors(
	transistors: Array[NetlistParser.ParsedComponent],
	node_canvas: Dictionary,
	placed_components: Dictionary,
	node_to_pins: Dictionary
) -> void:
	for c in transistors:
		var n_b = c.pins.get("B", "")
		var n_c = c.pins.get("C", "")
		var n_e = c.pins.get("E", "")

		var p_b = node_canvas.get(n_b, Vector2(200.0, 360.0))
		var p_c = node_canvas.get(n_c, Vector2(440.0, 200.0))
		var p_e = node_canvas.get(n_e, Vector2(440.0, 520.0))

		# Optimal schematic placement between base input and collector/emitter vertical rail
		var x_pos: float
		if abs(p_c.x - p_b.x) > 40.0:
			x_pos = (p_b.x + p_c.x) / 2.0
		else:
			x_pos = p_c.x - 80.0

		var y_pos: float
		if abs(p_c.y - p_e.y) > 40.0:
			y_pos = (p_c.y + p_e.y) / 2.0
		else:
			y_pos = p_b.y

		# Snap to 20px grid
		var comp_pos = Vector2(
			round(x_pos / GRID_SNAP) * GRID_SNAP,
			round(y_pos / GRID_SNAP) * GRID_SNAP
		)

		var rot_deg = 0
		if p_b.x > p_c.x:
			rot_deg = 180

		var comp = CircuitComponent.new(c.id, c.type, comp_pos, c.value)
		comp.rotation_deg = rot_deg
		placed_components[c.id] = comp

		# Register pins into electrical node graph
		_register_node_pin(node_to_pins, n_b, c.id + ":B")
		_register_node_pin(node_to_pins, n_c, c.id + ":C")
		_register_node_pin(node_to_pins, n_e, c.id + ":E")

static func _register_node_pin(dict: Dictionary, nid: String, pin_id: String) -> void:
	if not dict.has(nid):
		dict[nid] = []
	if not dict[nid].has(pin_id):
		dict[nid].append(pin_id)
