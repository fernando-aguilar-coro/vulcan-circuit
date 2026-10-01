class_name BranchClassifier
extends RefCounted

## BranchClassifier: Classifies branches, manages source virtualization, and computes deterministic orientations.

class BranchPlacement:
	var comp: NetlistParser.ParsedComponent
	var is_spanning: bool = false
	var bypass_level: int = 1
	var parallel_idx: int = 0
	var parallel_total: int = 1

static func virtualize_ground_sources(
	parse_result: NetlistParser.ParseResult,
	placed_components: Dictionary,
	node_to_pins: Dictionary
) -> Dictionary:
	var gnd_id = parse_result.gnd_node
	var rail_nodes: Dictionary = {}

	for c in parse_result.components:
		if c.type == CircuitComponent.Type.VOLTAGE_SOURCE and (c.from_node == gnd_id or c.to_node == gnd_id):
			var is_pos = (c.to_node == gnd_id)
			var rail_nid = c.from_node if is_pos else c.to_node

			var label_str = ""
			var node_obj = parse_result.nodes.get(rail_nid)
			if node_obj and node_obj.net_label != "":
				label_str = node_obj.net_label
			elif c.value != "":
				var val_clean = c.value.trim_suffix("V").trim_suffix("v").strip_edges()
				label_str = ("+" if is_pos else "-") + val_clean + "V"
			else:
				label_str = "VCC" if is_pos else "VEE"

			rail_nodes[rail_nid] = label_str

			var virt_comp = CircuitComponent.new(c.id, c.type, Vector2.ZERO, c.value)
			virt_comp.is_virtual = true
			virt_comp.display_label = label_str
			placed_components[c.id] = virt_comp

			_register_node_pin(node_to_pins, c.from_node, c.id + ":pos")
			_register_node_pin(node_to_pins, c.to_node, c.id + ":neg")

	return rail_nodes

static func classify_branches(
	components: Array[NetlistParser.ParsedComponent],
	parse_result: NetlistParser.ParseResult
) -> Array[BranchPlacement]:
	var list: Array[BranchPlacement] = []
	var pair_groups: Dictionary = {}

	for c in components:
		# Transistors are handled separately
		if c.type == CircuitComponent.Type.BJT_NPN or c.type == CircuitComponent.Type.BJT_PNP:
			continue
		var key = _pair_key(c.from_node, c.to_node)
		if not pair_groups.has(key):
			pair_groups[key] = []
		pair_groups[key].append(c)

	var bypass_counter := 1
	for key in pair_groups:
		var group: Array = pair_groups[key]
		var total = group.size()
		for idx in range(total):
			var c: NetlistParser.ParsedComponent = group[idx]
			var bp = BranchPlacement.new()
			bp.comp = c
			bp.parallel_idx = idx
			bp.parallel_total = total

			var na = parse_result.nodes.get(c.from_node)
			var nb = parse_result.nodes.get(c.to_node)
			if na and nb and na.has_pos and nb.has_pos:
				var span_x = abs(nb.pos.x - na.pos.x)
				var is_same_row = (na.pos.y == nb.pos.y)
				if is_same_row and (span_x > 2 or idx > 0):
					bp.is_spanning = true
					bp.bypass_level = bypass_counter
					bypass_counter += 1

			list.append(bp)

	return list

static func calculate_deterministic_rotation(
	comp: NetlistParser.ParsedComponent,
	node_a: NetlistParser.ParsedNode,
	node_b: NetlistParser.ParsedNode,
	fallback_p_from: Vector2,
	fallback_p_to: Vector2
) -> int:
	var dx := 0
	var dy := 0
	if node_a and node_b and node_a.has_pos and node_b.has_pos:
		dx = node_b.pos.x - node_a.pos.x
		dy = node_b.pos.y - node_a.pos.y
	else:
		var delta = fallback_p_to - fallback_p_from
		dx = int(round(delta.x / 10.0))
		dy = int(round(delta.y / 10.0))

	var is_horiz = abs(dx) >= abs(dy)
	if is_horiz:
		var from_is_left = dx >= 0
		match comp.type:
			CircuitComponent.Type.VOLTAGE_SOURCE:
				return 270 if from_is_left else 90
			CircuitComponent.Type.CURRENT_SOURCE:
				return 90 if from_is_left else 270
			_:
				return 0 if from_is_left else 180
	else:
		var from_is_top = dy >= 0
		match comp.type:
			CircuitComponent.Type.VOLTAGE_SOURCE:
				return 0 if from_is_top else 180
			CircuitComponent.Type.CURRENT_SOURCE:
				return 180 if from_is_top else 0
			_:
				return 90 if from_is_top else 270

static func _pair_key(a: String, b: String) -> String:
	return a + "__" + b if a < b else b + "__" + a

static func _register_node_pin(dict: Dictionary, nid: String, pin_id: String) -> void:
	if not dict.has(nid): dict[nid] = []
	if not dict[nid].has(pin_id): dict[nid].append(pin_id)
