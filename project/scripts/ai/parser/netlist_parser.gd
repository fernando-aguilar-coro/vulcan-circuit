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
	var model_name: String = ""
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
				comp.model_name = model_val if model_val != "" else ("2N2222" if comp.type == CircuitComponent.Type.BJT_NPN else "2N2907")
				comp.value = comp.model_name
				comp.pins["C"] = n_c
				comp.pins["B"] = n_b
				comp.pins["E"] = n_e
				comp.connected_nodes = [n_c, n_b, n_e]
				_ensure_node(res, n_c)
				_ensure_node(res, n_b)
				_ensure_node(res, n_e)
				res.components.append(comp)
				continue

		# Potentiometer / Trimpot: XPOT<id> <t1> <wiper> <t2> [POT] [value]
		if comp.type == CircuitComponent.Type.POTENTIOMETER:
			if tokens.size() >= 4:
				var n_t1 = _normalize_node(tokens[1])
				var n_w = _normalize_node(tokens[2])
				var n_t2 = _normalize_node(tokens[3])
				comp.pins["t1"] = n_t1
				comp.pins["wiper"] = n_w
				comp.pins["t2"] = n_t2
				comp.connected_nodes = [n_t1, n_w, n_t2]
				comp.from_node = n_t1
				comp.to_node = n_t2
				var val = "10k"
				for k in range(4, tokens.size()):
					var tk = tokens[k].strip_edges()
					if tk.to_upper() != "POT" and not tk.begins_with("*"):
						val = tk
						break
				comp.value = val
				_ensure_node(res, n_t1)
				_ensure_node(res, n_w)
				_ensure_node(res, n_t2)
				res.components.append(comp)
				continue

		# Transformer: XTR<id> <pri+> <pri-> <sec+> <sec-> [XFMR] [ratio]
		if comp.type == CircuitComponent.Type.TRANSFORMER:
			if tokens.size() >= 5:
				var p_pos = _normalize_node(tokens[1])
				var p_neg = _normalize_node(tokens[2])
				var s_pos = _normalize_node(tokens[3])
				var s_neg = _normalize_node(tokens[4])
				comp.pins["pri_pos"] = p_pos
				comp.pins["pri_neg"] = p_neg
				comp.pins["sec_pos"] = s_pos
				comp.pins["sec_neg"] = s_neg
				comp.connected_nodes = [p_pos, p_neg, s_pos, s_neg]
				comp.from_node = p_pos
				comp.to_node = s_pos
				var val = "1:1"
				if tokens.size() >= 6:
					var tk = tokens[tokens.size() - 1].strip_edges()
					if tk.to_upper() != "XFMR" and not tk.begins_with("*"): val = tk
				comp.value = val
				_ensure_node(res, p_pos)
				_ensure_node(res, p_neg)
				_ensure_node(res, s_pos)
				_ensure_node(res, s_neg)
				res.components.append(comp)
				continue

		# SCR (Thyristor): XSCR<id> <anode> <gate> <cathode> [model]
		if comp.type == CircuitComponent.Type.SCR:
			if tokens.size() >= 4:
				var n_a = _normalize_node(tokens[1])
				var n_g = _normalize_node(tokens[2])
				var n_k = _normalize_node(tokens[3])
				comp.pins["anode"] = n_a
				comp.pins["gate"] = n_g
				comp.pins["cathode"] = n_k
				comp.connected_nodes = [n_a, n_g, n_k]
				comp.from_node = n_a
				comp.to_node = n_k
				comp.value = tokens[4] if tokens.size() >= 5 and not tokens[4].begins_with("*") else "2N5064"
				_ensure_node(res, n_a)
				_ensure_node(res, n_g)
				_ensure_node(res, n_k)
				res.components.append(comp)
				continue

		# TRIAC: XTRIAC<id> <mt2> <gate> <mt1> [model]
		if comp.type == CircuitComponent.Type.TRIAC:
			if tokens.size() >= 4:
				var n_mt2 = _normalize_node(tokens[1])
				var n_g = _normalize_node(tokens[2])
				var n_mt1 = _normalize_node(tokens[3])
				comp.pins["mt2"] = n_mt2
				comp.pins["gate"] = n_g
				comp.pins["mt1"] = n_mt1
				comp.connected_nodes = [n_mt2, n_g, n_mt1]
				comp.from_node = n_mt2
				comp.to_node = n_mt1
				comp.value = tokens[4] if tokens.size() >= 5 and not tokens[4].begins_with("*") else "BT136"
				_ensure_node(res, n_mt2)
				_ensure_node(res, n_g)
				_ensure_node(res, n_mt1)
				res.components.append(comp)
				continue

		# Operational Amplifier: XOP<id> <in+> <in-> <out> [model]
		if comp.type == CircuitComponent.Type.OPAMP:
			if tokens.size() >= 4:
				var n_pos = _normalize_node(tokens[1])
				var n_neg = _normalize_node(tokens[2])
				var n_out = _normalize_node(tokens[3])
				var model_val = "LM741"
				if tokens.size() >= 6 and not _is_likely_model(tokens[5]):
					var n_vcc = _normalize_node(tokens[3])
					var n_vee = _normalize_node(tokens[4])
					n_out = _normalize_node(tokens[5])
					model_val = tokens[6] if tokens.size() >= 7 and not tokens[6].begins_with("*") else "LM741"
					comp.pins["vcc"] = n_vcc
					comp.pins["vee"] = n_vee
					_ensure_node(res, n_vcc)
					_ensure_node(res, n_vee)
					comp.connected_nodes = [n_pos, n_neg, n_vcc, n_vee, n_out]
				else:
					model_val = tokens[4] if tokens.size() >= 5 and not tokens[4].begins_with("*") else "LM741"
					comp.connected_nodes = [n_pos, n_neg, n_out]
				comp.pins["in_pos"] = n_pos
				comp.pins["in_neg"] = n_neg
				comp.pins["out"] = n_out
				comp.from_node = n_pos
				comp.to_node = n_out
				comp.value = model_val
				comp.model_name = model_val
				_ensure_node(res, n_pos)
				_ensure_node(res, n_neg)
				_ensure_node(res, n_out)
				res.components.append(comp)
				continue

		# Generic ICs and Subcircuits (Regulators, Optocouplers, Sensors, MUX, etc.)
		if comp.type == CircuitComponent.Type.IC:
			if tokens.size() >= 3:
				var last_token = tokens[tokens.size() - 1].strip_edges()
				var has_model = _is_likely_model(last_token)
				var node_tokens: Array = []
				var model_name = last_token if has_model else comp.id
				var end_idx = tokens.size() - 1 if has_model else tokens.size()
				for k in range(1, end_idx):
					var tk = tokens[k].strip_edges()
					if not tk.begins_with("*"):
						node_tokens.append(_normalize_node(tk))

				comp.connected_nodes = node_tokens
				comp.model_name = model_name
				comp.value = model_name
				var u_mod = model_name.to_upper()
				var u_id = comp.id.to_upper()

				if node_tokens.size() == 3 and (u_mod.contains("78") or u_mod.contains("79") or u_mod.contains("317") or u_mod.contains("1117") or u_id.begins_with("XREG")):
					comp.pins["IN"] = node_tokens[0]
					comp.pins["GND"] = node_tokens[1]
					comp.pins["OUT"] = node_tokens[2]
				elif node_tokens.size() == 4 and (u_mod.contains("PC817") or u_mod.contains("4N") or u_id.begins_with("XOPTO")):
					comp.pins["A"] = node_tokens[0]
					comp.pins["K"] = node_tokens[1]
					comp.pins["E"] = node_tokens[2]
					comp.pins["C"] = node_tokens[3]
				elif node_tokens.size() == 3 and (u_mod.contains("431") or u_id.begins_with("XREF")):
					comp.pins["K"] = node_tokens[0]
					comp.pins["A"] = node_tokens[1]
					comp.pins["REF"] = node_tokens[2]
				elif node_tokens.size() == 3 and (u_mod.contains("LM35") or u_mod.contains("TMP") or u_id.begins_with("XSENS")):
					comp.pins["VCC"] = node_tokens[0]
					comp.pins["GND"] = node_tokens[1]
					comp.pins["VOUT"] = node_tokens[2]
				else:
					for p_idx in range(node_tokens.size()):
						comp.pins["p" + str(p_idx + 1)] = node_tokens[p_idx]

				for nid in node_tokens:
					_ensure_node(res, nid)

				if not node_tokens.is_empty():
					comp.from_node = node_tokens[0]
					comp.to_node = node_tokens[node_tokens.size() - 1]

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
			var u_nid = raw_nid.to_upper()
			var is_node = u_nid == "0" or u_nid == "GND" or u_nid.is_valid_int() or (u_nid.begins_with("N") and u_nid.length() > 1 and u_nid.substr(1).is_valid_int())
			if not is_node:
				continue
			if not (tokens[1].is_valid_int() and tokens[2].is_valid_int()):
				continue

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
	if u.begins_with("XPOT") or u.begins_with("RPOT") or u.begins_with("POT"):
		return CircuitComponent.Type.POTENTIOMETER
	if u.begins_with("XTR") or u.begins_with("TR") or u.begins_with("TX"):
		return CircuitComponent.Type.TRANSFORMER
	if u.begins_with("XSCR") or u.begins_with("SCR"):
		return CircuitComponent.Type.SCR
	if u.begins_with("XTRIAC") or u.begins_with("TRIAC"):
		return CircuitComponent.Type.TRIAC
	if u.begins_with("XOPTO"):
		return CircuitComponent.Type.IC
	if (u.begins_with("XOP") or u.begins_with("OP")) and not u.begins_with("XOPTO"):
		return CircuitComponent.Type.OPAMP
	if u.begins_with("X") or u.begins_with("U"):
		return CircuitComponent.Type.IC
	if u.begins_with("R"):
		return CircuitComponent.Type.RESISTOR
	return CircuitComponent.Type.RESISTOR

static func _is_likely_model(token: String) -> bool:
	var s = token.strip_edges()
	var u = s.to_upper()
	if u in ["DC", "AC", "GND"]: return false
	if (u.begins_with("N") and u.substr(1).is_valid_int()) or u.is_valid_int():
		return false
	return true

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
