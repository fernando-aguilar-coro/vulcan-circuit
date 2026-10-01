class_name DipolePlacer
extends RefCounted

## DipolePlacer: Orchestrates schematic layout, source virtualization, 
## transistor placement, and star-junction routing.

const PITCH_X: float = 240.0
const PITCH_Y: float = 180.0
const ORIGIN: Vector2 = Vector2(200.0, 180.0)
const BYPASS_HEIGHT: float = 85.0
const PARALLEL_STEP: float = 70.0

static func place_circuit(parse_result: NetlistParser.ParseResult) -> Dictionary:
	if parse_result.components.is_empty():
		return {"success": false, "components": {}, "wires": []}

	var placed_components: Dictionary = {}
	var node_to_pins: Dictionary = {}

	# 1. Virtualize Ground-Referenced Voltage Sources
	var rail_nodes = BranchClassifier.virtualize_ground_sources(
		parse_result,
		placed_components,
		node_to_pins
	)

	# 2. Node grid coordinates
	var node_canvas: Dictionary = _calculate_node_canvas_positions(parse_result)

	# 3. Separate transistors and active 2-terminal dipoles
	var transistors: Array[NetlistParser.ParsedComponent] = []
	var dipole_components: Array[NetlistParser.ParsedComponent] = []

	for c in parse_result.components:
		if placed_components.has(c.id) and placed_components[c.id].is_virtual:
			continue
		if c.type == CircuitComponent.Type.BJT_NPN or c.type == CircuitComponent.Type.BJT_PNP:
			transistors.append(c)
		else:
			dipole_components.append(c)

	# 4. Place 3-terminal active devices (Transistors)
	TransistorPlacer.place_transistors(
		transistors,
		node_canvas,
		placed_components,
		node_to_pins
	)

	# 5. Classify and place 2-terminal dipoles
	var branch_placements = BranchClassifier.classify_branches(dipole_components, parse_result)
	var comp_placement_map: Dictionary = {}

	for bp in branch_placements:
		var c = bp.comp
		var p_from = node_canvas.get(c.from_node, ORIGIN)
		var p_to = node_canvas.get(c.to_node, ORIGIN)
		var comp_pos = Vector2.ZERO
		var node_a = parse_result.nodes.get(c.from_node)
		var node_b = parse_result.nodes.get(c.to_node)
		var rot_deg = BranchClassifier.calculate_deterministic_rotation(c, node_a, node_b, p_from, p_to)

		if bp.is_spanning:
			var center_x = (p_from.x + p_to.x) / 2.0
			var channel_y = p_from.y - (BYPASS_HEIGHT * bp.bypass_level)
			comp_pos = Vector2(center_x, channel_y)
		else:
			var edge_vec = p_to - p_from
			var mid = (p_from + p_to) / 2.0
			var is_horiz = abs(edge_vec.x) >= abs(edge_vec.y)

			if bp.parallel_total > 1:
				var normal = Vector2(0.0, -1.0) if is_horiz else Vector2(1.0, 0.0)
				var offset_step = (float(bp.parallel_idx) - float(bp.parallel_total - 1) / 2.0) * PARALLEL_STEP
				mid += normal * offset_step

			comp_pos = mid

		var comp = CircuitComponent.new(c.id, c.type, comp_pos, c.value)
		comp.rotation_deg = rot_deg
		placed_components[c.id] = comp
		comp_placement_map[c.id] = bp

		var p_from_name = _get_pin_name(c.type, true)
		var p_to_name = _get_pin_name(c.type, false)
		_register_node_pin(node_to_pins, c.from_node, c.id + ":" + p_from_name)
		_register_node_pin(node_to_pins, c.to_node, c.id + ":" + p_to_name)

	# 6. Place local NetLabels and local Ground symbols
	_place_labels_and_ground(parse_result, node_canvas, rail_nodes, placed_components, node_to_pins)

	# 7. Route mesh wires using EDA Star-Junction pattern
	var wires = StarJunctionRouter.route_mesh_wires(
		placed_components,
		comp_placement_map,
		node_to_pins,
		node_canvas
	)

	return {
		"success": true,
		"components": placed_components,
		"wires": wires
	}

static func _calculate_node_canvas_positions(parse_result: NetlistParser.ParseResult) -> Dictionary:
	var canvas_pos: Dictionary = {}
	var unplaced_x := 0
	for nid in parse_result.nodes:
		var node = parse_result.nodes[nid]
		if node.has_pos:
			canvas_pos[nid] = ORIGIN + Vector2(node.pos.x * PITCH_X, node.pos.y * PITCH_Y)
		else:
			canvas_pos[nid] = ORIGIN + Vector2(unplaced_x * PITCH_X, 2 * PITCH_Y)
			unplaced_x += 2
	return canvas_pos

static func _place_labels_and_ground(
	res: NetlistParser.ParseResult,
	node_canvas: Dictionary,
	rail_nodes: Dictionary,
	components: Dictionary,
	node_to_pins: Dictionary
) -> void:
	var gnd_id = res.gnd_node

	for rail_nid in rail_nodes:
		var lbl_text = rail_nodes[rail_nid]
		var pos = node_canvas.get(rail_nid, ORIGIN)
		var lbl_id = "LBL_" + rail_nid
		var lbl_comp = CircuitComponent.new(lbl_id, CircuitComponent.Type.NET_LABEL, pos, lbl_text)
		components[lbl_id] = lbl_comp
		_register_node_pin(node_to_pins, rail_nid, lbl_id + ":pin")

	if node_canvas.has(gnd_id):
		var g_pos = node_canvas[gnd_id] + Vector2(0.0, 20.0)
		var gnd_id_str = "GND_" + gnd_id
		var gnd_comp = CircuitComponent.new(gnd_id_str, CircuitComponent.Type.GROUND, g_pos, "0")
		components[gnd_id_str] = gnd_comp
		_register_node_pin(node_to_pins, gnd_id, gnd_id_str + ":gnd")

	for nid in res.nodes:
		var node = res.nodes[nid]
		if node.net_label != "" and nid != gnd_id and not rail_nodes.has(nid):
			var pos = node_canvas.get(nid, ORIGIN)
			var lbl_id = "LBL_" + nid
			var lbl_comp = CircuitComponent.new(lbl_id, CircuitComponent.Type.NET_LABEL, pos, node.net_label)
			components[lbl_id] = lbl_comp
			_register_node_pin(node_to_pins, nid, lbl_id + ":pin")

static func _get_pin_name(ctype: CircuitComponent.Type, is_from: bool) -> String:
	match ctype:
		CircuitComponent.Type.VOLTAGE_SOURCE: return "pos" if is_from else "neg"
		CircuitComponent.Type.CURRENT_SOURCE: return "neg" if is_from else "pos"
		CircuitComponent.Type.DIODE: return "anode" if is_from else "cathode"
		_: return "p1" if is_from else "p2"

static func _register_node_pin(dict: Dictionary, nid: String, pin_id: String) -> void:
	if not dict.has(nid): dict[nid] = []
	if not dict[nid].has(pin_id): dict[nid].append(pin_id)
