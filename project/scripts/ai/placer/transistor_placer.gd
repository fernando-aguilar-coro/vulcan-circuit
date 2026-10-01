class_name TransistorPlacer
extends RefCounted

## TransistorPlacer: Positions 3+ terminal active devices and ICs on the schematic grid.

const GRID_SNAP: float = 20.0
const ORIGIN: Vector2 = Vector2(200.0, 180.0)

static func place_multi_terminal(
	components_list: Array[NetlistParser.ParsedComponent],
	node_canvas: Dictionary,
	placed_components: Dictionary,
	node_to_pins: Dictionary
) -> void:
	for c in components_list:
		match c.type:
			CircuitComponent.Type.BJT_NPN, CircuitComponent.Type.BJT_PNP:
				_place_bjt(c, node_canvas, placed_components, node_to_pins)
			CircuitComponent.Type.POTENTIOMETER:
				_place_potentiometer(c, node_canvas, placed_components, node_to_pins)
			CircuitComponent.Type.TRANSFORMER:
				_place_transformer(c, node_canvas, placed_components, node_to_pins)
			CircuitComponent.Type.SCR, CircuitComponent.Type.TRIAC:
				_place_thyristor(c, node_canvas, placed_components, node_to_pins)
			CircuitComponent.Type.OPAMP:
				_place_opamp(c, node_canvas, placed_components, node_to_pins)
			CircuitComponent.Type.IC:
				_place_ic(c, node_canvas, placed_components, node_to_pins)
			_:
				_place_generic_multi(c, node_canvas, placed_components, node_to_pins)

static func place_transistors(
	transistors: Array[NetlistParser.ParsedComponent],
	node_canvas: Dictionary,
	placed_components: Dictionary,
	node_to_pins: Dictionary
) -> void:
	place_multi_terminal(transistors, node_canvas, placed_components, node_to_pins)

static func _place_bjt(
	c: NetlistParser.ParsedComponent,
	node_canvas: Dictionary,
	placed_components: Dictionary,
	node_to_pins: Dictionary
) -> void:
	var n_b = c.pins.get("B", "")
	var n_c = c.pins.get("C", "")
	var n_e = c.pins.get("E", "")

	var p_b = node_canvas.get(n_b, Vector2(200.0, 360.0))
	var p_c = node_canvas.get(n_c, Vector2(440.0, 200.0))
	var p_e = node_canvas.get(n_e, Vector2(440.0, 520.0))

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

	_register_node_pin(node_to_pins, n_b, c.id + ":B")
	_register_node_pin(node_to_pins, n_c, c.id + ":C")
	_register_node_pin(node_to_pins, n_e, c.id + ":E")

static func _place_potentiometer(
	c: NetlistParser.ParsedComponent,
	node_canvas: Dictionary,
	placed_components: Dictionary,
	node_to_pins: Dictionary
) -> void:
	var n_t1 = c.pins.get("t1", "")
	var n_w = c.pins.get("wiper", "")
	var n_t2 = c.pins.get("t2", "")

	var p_t1 = node_canvas.get(n_t1, ORIGIN)
	var p_t2 = node_canvas.get(n_t2, ORIGIN)
	var mid = (p_t1 + p_t2) / 2.0

	var comp_pos = Vector2(
		round(mid.x / GRID_SNAP) * GRID_SNAP,
		round(mid.y / GRID_SNAP) * GRID_SNAP
	)

	var rot_deg = 0
	if abs(p_t2.y - p_t1.y) > abs(p_t2.x - p_t1.x) + 20.0:
		rot_deg = 90

	var comp = CircuitComponent.new(c.id, c.type, comp_pos, c.value)
	comp.rotation_deg = rot_deg
	placed_components[c.id] = comp

	_register_node_pin(node_to_pins, n_t1, c.id + ":t1")
	_register_node_pin(node_to_pins, n_t2, c.id + ":t2")
	_register_node_pin(node_to_pins, n_w, c.id + ":wiper")

static func _place_transformer(
	c: NetlistParser.ParsedComponent,
	node_canvas: Dictionary,
	placed_components: Dictionary,
	node_to_pins: Dictionary
) -> void:
	var comp_pos = _calc_centroid(c.connected_nodes, node_canvas)
	var comp = CircuitComponent.new(c.id, c.type, comp_pos, c.value)
	placed_components[c.id] = comp

	for pin_name in c.pins:
		_register_node_pin(node_to_pins, c.pins[pin_name], c.id + ":" + pin_name)

static func _place_thyristor(
	c: NetlistParser.ParsedComponent,
	node_canvas: Dictionary,
	placed_components: Dictionary,
	node_to_pins: Dictionary
) -> void:
	var comp_pos = _calc_centroid(c.connected_nodes, node_canvas)
	var comp = CircuitComponent.new(c.id, c.type, comp_pos, c.value)
	placed_components[c.id] = comp

	for pin_name in c.pins:
		_register_node_pin(node_to_pins, c.pins[pin_name], c.id + ":" + pin_name)

static func _place_opamp(
	c: NetlistParser.ParsedComponent,
	node_canvas: Dictionary,
	placed_components: Dictionary,
	node_to_pins: Dictionary
) -> void:
	var comp_pos = _calc_centroid(c.connected_nodes, node_canvas)
	var comp = CircuitComponent.new(c.id, c.type, comp_pos, c.value)
	placed_components[c.id] = comp

	for pin_name in c.pins:
		_register_node_pin(node_to_pins, c.pins[pin_name], c.id + ":" + pin_name)

static func _place_ic(
	c: NetlistParser.ParsedComponent,
	node_canvas: Dictionary,
	placed_components: Dictionary,
	node_to_pins: Dictionary
) -> void:
	var comp_pos = _calc_centroid(c.connected_nodes, node_canvas)
	var comp = CircuitComponent.new(c.id, CircuitComponent.Type.IC, comp_pos, c.value)
	comp.setup_ic_pins(c.model_name, c.pins.keys())
	placed_components[c.id] = comp

	for pin_name in c.pins:
		_register_node_pin(node_to_pins, c.pins[pin_name], c.id + ":" + pin_name)

static func _place_generic_multi(
	c: NetlistParser.ParsedComponent,
	node_canvas: Dictionary,
	placed_components: Dictionary,
	node_to_pins: Dictionary
) -> void:
	var comp_pos = _calc_centroid(c.connected_nodes, node_canvas)
	var comp = CircuitComponent.new(c.id, c.type, comp_pos, c.value)
	placed_components[c.id] = comp

	for pin_name in c.pins:
		_register_node_pin(node_to_pins, c.pins[pin_name], c.id + ":" + pin_name)

static func _calc_centroid(connected_nodes: Array, node_canvas: Dictionary) -> Vector2:
	var sum_pos = Vector2.ZERO
	var count = 0
	for nid in connected_nodes:
		if node_canvas.has(str(nid)):
			sum_pos += node_canvas[str(nid)]
			count += 1
	var center = sum_pos / float(count) if count > 0 else ORIGIN
	return Vector2(
		round(center.x / GRID_SNAP) * GRID_SNAP,
		round(center.y / GRID_SNAP) * GRID_SNAP
	)

static func _register_node_pin(dict: Dictionary, nid: String, pin_id: String) -> void:
	if not dict.has(nid):
		dict[nid] = []
	if not dict[nid].has(pin_id):
		dict[nid].append(pin_id)
