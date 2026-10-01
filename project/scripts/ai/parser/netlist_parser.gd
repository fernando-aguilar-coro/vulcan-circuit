class_name NetlistParser
extends RefCounted

## NetlistParser: Compact SPICE & Node Positions Parser with NetLabel support.

class ParsedNode:
	var id: String = ""
	var pos: Vector2i = Vector2i.ZERO
	var has_pos: bool = false
	var is_gnd: bool = false
	var net_label: String = ""

class ParsedComponent:
	var id: String = ""
	var type: CircuitComponent.Type = CircuitComponent.Type.RESISTOR
	var value: String = ""
	var from_node: String = ""
	var to_node: String = ""
	var pins: Dictionary = {}
	var connected_nodes: Array = []

class ParseResult:
	var nodes: Dictionary = {} # node_id -> ParsedNode
	var components: Array[ParsedComponent] = []
	var gnd_node: String = "0"
	var title: String = ""

static func parse(ai_text: String) -> ParseResult:
	var clean = ai_text.strip_edges()
	if clean.begins_with("```"):
		var first_nl = clean.find("\n")
		var last_fence = clean.rfind("```")
		if first_nl != -1 and last_fence > first_nl:
			clean = clean.substr(first_nl + 1, last_fence - first_nl - 1).strip_edges()

	if clean.begins_with("{"):
		var json = JSON.parse_string(clean)
		if typeof(json) == TYPE_DICTIONARY:
			return _parse_json_dict(json)

	return _parse_spice_text(clean)

static func _parse_spice_text(text: String) -> ParseResult:
	var res = ParseResult.new()
	var lines = text.split("\n")
	var in_positions := false

	for raw_line in lines:
		var line = raw_line.strip_edges()
		if line.is_empty():
			continue

		var lower = line.to_lower()
		if lower.begins_with("* positions") or lower.begins_with("* node positions"):
			in_positions = true
			var colon = line.find(":")
			if colon != -1:
				_parse_positions_line(line.substr(colon + 1), res)
			continue

		if in_positions:
			if line.begins_with("*") and not (line.contains(";") or _contains_coords(line)):
				in_positions = false
			elif _parse_positions_line(line.trim_prefix("*").strip_edges(), res):
				continue
			else:
				in_positions = false

		if _contains_coords(line) and _parse_positions_line(line.trim_prefix("*").strip_edges(), res):
			continue

		# Explicit label directive: .label <node> <label> or * label <node> <label>
		if lower.begins_with(".label") or lower.begins_with("* label"):
			var parts = line.split(" ", false)
			if parts.size() >= 3:
				var nid = _normalize_node(parts[parts.size() - 2])
				var lbl = parts[parts.size() - 1].strip_edges()
				_ensure_node(res, nid).net_label = lbl
			continue

		if line.begins_with("*") or line.begins_with("."):
			continue

		# Parse component line: <ID> <NODE_A> <NODE_B> [DC/AC] <VALUE>
		var tokens = line.split(" ", false)
		if tokens.size() < 3:
			continue

		var comp = ParsedComponent.new()
		comp.id = tokens[0]
		comp.type = _infer_type(comp.id)

		# BJT Transistor: Q<id> <collector> <base> <emitter> [model]
		if comp.type == CircuitComponent.Type.BJT_NPN or comp.type == CircuitComponent.Type.BJT_PNP:
			if tokens.size() >= 4:
				var n_c = _normalize_node(tokens[1])
				var n_b = _normalize_node(tokens[2])
				var n_e = _normalize_node(tokens[3])
				comp.from_node = n_b
				comp.to_node = n_c
				var model_val = tokens[4] if tokens.size() >= 5 else ""
				var u_mod = model_val.to_upper()
				if u_mod.contains("PNP") or u_mod.contains("2N2907") or u_mod.contains("BC557"):
					comp.type = CircuitComponent.Type.BJT_PNP
				elif u_mod != "":
					comp.type = CircuitComponent.Type.BJT_NPN
				comp.value = model_val if model_val != "" else ("2N2222" if comp.type == CircuitComponent.Type.BJT_NPN else "2N2907")
				comp.pins["C"] = n_c
				comp.pins["B"] = n_b
				comp.pins["E"] = n_e
				comp.connected_nodes = [n_c, n_b, n_e]
				_ensure_node(res, n_c)
				_ensure_node(res, n_b)
				_ensure_node(res, n_e)
				res.components.append(comp)
				continue

		comp.from_node = _normalize_node(tokens[1])
		comp.to_node = _normalize_node(tokens[2])

		# Value
		if tokens.size() >= 5 and (tokens[3].to_upper() in ["DC", "AC"]):
			comp.value = tokens[4]
		elif tokens.size() >= 4:
			comp.value = tokens[3]
		else:
			comp.value = "1k"

		_setup_dipole_pins(comp, comp.from_node, comp.to_node)
		_ensure_node(res, comp.from_node)
		_ensure_node(res, comp.to_node)
		res.components.append(comp)

	if res.nodes.has("0"):
		res.gnd_node = "0"
		res.nodes["0"].is_gnd = true
	elif res.nodes.has("GND"):
		res.gnd_node = "GND"
		res.nodes["GND"].is_gnd = true

	return res

static func _contains_coords(line: String) -> bool:
	var l = line.to_upper()
	if l.contains(";") and (l.contains(",") or l.contains(" ")):
		return true
	for i in range(10):
		if l.contains("N" + str(i)) and l.contains(","):
			return true
	return false

static func _parse_positions_line(line: String, res: ParseResult) -> bool:
	var items = line.split(";")
	var parsed_any := false
	for raw_item in items:
		var item = raw_item.strip_edges().replace(",", " ").replace(":", " ")
		var tokens = item.split(" ", false)
		if tokens.size() >= 3:
			var raw_nid = tokens[0]
			var x = int(tokens[1])
			var y = int(tokens[2])
			var nid = _normalize_node(raw_nid)
			_register_node_pos(res, nid, Vector2i(x, y))
			if raw_nid != nid:
				_register_node_pos(res, raw_nid, Vector2i(x, y))
			parsed_any = true
	return parsed_any

static func _register_node_pos(res: ParseResult, nid: String, pos: Vector2i) -> void:
	var node = _ensure_node(res, nid)
	node.pos = pos
	node.has_pos = true
	if nid == "0" or nid == "GND":
		node.is_gnd = true

static func _ensure_node(res: ParseResult, nid: String) -> ParsedNode:
	if not res.nodes.has(nid):
		var node = ParsedNode.new()
		node.id = nid
		node.is_gnd = (nid == "0" or nid == "GND")
		if _is_net_label(nid):
			node.net_label = nid
		res.nodes[nid] = node
	return res.nodes[nid]

static func _is_net_label(nid: String) -> bool:
	var u = nid.to_upper()
	return nid.begins_with("+") or nid.begins_with("-") or u in ["VCC", "VDD", "VEE", "VSS", "GND"]

static func _setup_dipole_pins(comp: ParsedComponent, n_a: String, n_b: String) -> void:
	comp.connected_nodes = [n_a, n_b]
	match comp.type:
		CircuitComponent.Type.VOLTAGE_SOURCE:
			comp.pins["pos"] = n_a
			comp.pins["neg"] = n_b
		CircuitComponent.Type.CURRENT_SOURCE:
			# SPICE: Ixxx N_from N_to (current leaves n_a into n_b)
			# Renderer arrow tip is at pos (n_b), tail is at neg (n_a)
			comp.pins["pos"] = n_b
			comp.pins["neg"] = n_a
		CircuitComponent.Type.DIODE:
			comp.pins["anode"] = n_a
			comp.pins["cathode"] = n_b
		_:
			comp.pins["p1"] = n_a
			comp.pins["p2"] = n_b

static func _infer_type(comp_id: String) -> CircuitComponent.Type:
	var u = comp_id.to_upper()
	if u.begins_with("V"): return CircuitComponent.Type.VOLTAGE_SOURCE
	if u.begins_with("I"): return CircuitComponent.Type.CURRENT_SOURCE
	if u.begins_with("C"): return CircuitComponent.Type.CAPACITOR
	if u.begins_with("L"): return CircuitComponent.Type.INDUCTOR
	if u.begins_with("D"): return CircuitComponent.Type.DIODE
	if u.begins_with("GND"): return CircuitComponent.Type.GROUND
	if u.begins_with("LBL"): return CircuitComponent.Type.NET_LABEL
	if u.begins_with("Q"):
		if u.contains("PNP") or u.contains("2N2907") or u.contains("BC557"):
			return CircuitComponent.Type.BJT_PNP
		return CircuitComponent.Type.BJT_NPN
	return CircuitComponent.Type.RESISTOR

static func _normalize_node(n: String) -> String:
	var s = n.strip_edges()
	if s.to_lower() == "gnd":
		return "0"
	if (s.begins_with("N") or s.begins_with("n")) and s.length() > 1 and s.substr(1).is_valid_int():
		return s.substr(1)
	return s

static func _parse_json_dict(dict: Dictionary) -> ParseResult:
	var res = ParseResult.new()
	res.title = str(dict.get("title", ""))
	var raw_nodes = dict.get("nodes", {})
	if raw_nodes is Dictionary:
		for k in raw_nodes:
			var pos_val = raw_nodes[k]
			var nid = _normalize_node(str(k))
			if pos_val is Array and pos_val.size() >= 2:
				_register_node_pos(res, nid, Vector2i(int(pos_val[0]), int(pos_val[1])))
	for c_data in dict.get("components", []):
		if not (c_data is Dictionary): continue
		var comp = ParsedComponent.new()
		comp.id = str(c_data.get("id", ""))
		comp.type = _infer_type(comp.id)
		comp.value = str(c_data.get("value", "1k"))
		comp.from_node = _normalize_node(str(c_data.get("from_node", "")))
		comp.to_node = _normalize_node(str(c_data.get("to_node", "")))
		_setup_dipole_pins(comp, comp.from_node, comp.to_node)
		_ensure_node(res, comp.from_node)
		_ensure_node(res, comp.to_node)
		res.components.append(comp)
	if res.nodes.has("0"): res.gnd_node = "0"
	return res
