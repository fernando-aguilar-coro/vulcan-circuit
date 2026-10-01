class_name CircuitGraph
extends RefCounted

## CircuitGraph: Resolves netlist topology and produces SPICE netlists.

class NetlistResult:
	var netlist_text: String = ""
	var node_map: Dictionary = {} # pin_id -> node_name
	var net_groups: Dictionary = {} # node_name -> Array[String] (pin_ids)
	var warnings: Array[String] = []
	var errors: Array[String] = []
	var has_ground: bool = false

static func resolve_nets(components: Dictionary, wires: Array) -> NetlistResult:
	var result = NetlistResult.new()
	var dsu = DSU.new()
	var all_pins: Dictionary = {} # pin_id -> CircuitPin
	var ground_pins: Array[String] = []
	var label_groups: Dictionary = {} # normalized_label -> Array[String] (pin_ids)
	var labeled_roots: Dictionary = {} # pin_id -> explicit_name

	# 1. Register all pins and NetLabels
	for comp_id in components:
		var comp: CircuitComponent = components[comp_id]
		for pin in comp.pins:
			all_pins[pin.id] = pin
			dsu.make_set(pin.id)
			if pin.is_ground or comp.type == CircuitComponent.Type.GROUND:
				ground_pins.append(pin.id)
			elif comp.type == CircuitComponent.Type.NET_LABEL:
				var lbl = comp.value.strip_edges()
				var u_lbl = lbl.to_upper()
				if u_lbl == "0" or u_lbl == "GND":
					ground_pins.append(pin.id)
				else:
					if not label_groups.has(u_lbl):
						label_groups[u_lbl] = []
					label_groups[u_lbl].append(pin.id)
					labeled_roots[pin.id] = lbl

	# 2. Union pins connected by NetLabels sharing the same name
	for u_lbl in label_groups:
		var lpins: Array = label_groups[u_lbl]
		for i in range(lpins.size() - 1):
			dsu.union_sets(lpins[i], lpins[i + 1])

	# Connect virtual sources with their rail NetLabels and ground
	for comp_id in components:
		var comp: CircuitComponent = components[comp_id]
		if comp.is_virtual and comp.type == CircuitComponent.Type.VOLTAGE_SOURCE:
			ground_pins.append(comp.id + ":neg")
			var rail_lbl = comp.display_label.strip_edges().to_upper()
			if rail_lbl != "" and label_groups.has(rail_lbl):
				var lpins: Array = label_groups[rail_lbl]
				if not lpins.is_empty():
					dsu.union_sets(comp.id + ":pos", lpins[0])

	# 3. Union pins connected by wires
	for wire in wires:
		if all_pins.has(wire.from_pin_id) and all_pins.has(wire.to_pin_id):
			dsu.union_sets(wire.from_pin_id, wire.to_pin_id)
		else:
			result.warnings.append("Wire connects invalid pin: " + wire.from_pin_id + " -> " + wire.to_pin_id)

	# 4. Group pins by their root representative
	var root_to_pins: Dictionary = {} # root_id -> Array[String] (pin_ids)
	for pin_id in all_pins:
		var root = dsu.find_set(pin_id)
		if not root_to_pins.has(root):
			root_to_pins[root] = []
		root_to_pins[root].append(pin_id)

	# 5. Identify ground and explicit NetLabel roots
	var root_is_ground: Dictionary = {}
	for gnd_pin in ground_pins:
		var root = dsu.find_set(gnd_pin)
		root_is_ground[root] = true
		result.has_ground = true

	var root_explicit_name: Dictionary = {}
	for l_pin_id in labeled_roots:
		var root = dsu.find_set(l_pin_id)
		if not root_is_ground.get(root, false):
			root_explicit_name[root] = labeled_roots[l_pin_id]

	# 6. Assign SPICE node labels
	var root_to_node_name: Dictionary = {}
	var node_counter: int = 1

	for root in root_to_pins:
		if root_is_ground.get(root, false):
			root_to_node_name[root] = "0"
		elif root_explicit_name.has(root):
			root_to_node_name[root] = root_explicit_name[root]
		else:
			root_to_node_name[root] = "N" + str(node_counter)
			node_counter += 1

	# 7. Map every pin to its assigned node name and store net groups
	for root in root_to_pins:
		var node_name = root_to_node_name[root]
		if not result.net_groups.has(node_name):
			result.net_groups[node_name] = []
		result.net_groups[node_name].append_array(root_to_pins[root])
		for pin_id in root_to_pins[root]:
			result.node_map[pin_id] = node_name

	# 8. Check floating pins (NetLabels and pins attached to them are NEVER floating)
	for pin_id in all_pins:
		var pin: CircuitPin = all_pins[pin_id]
		var root = dsu.find_set(pin_id)
		if root_is_ground.get(root, false) or root_explicit_name.has(root):
			continue
		var comp_id = pin_id.split(":")[0]
		var comp: CircuitComponent = components.get(comp_id)
		if comp and (comp.is_virtual or comp.type == CircuitComponent.Type.GROUND or comp.type == CircuitComponent.Type.NET_LABEL or comp.type == CircuitComponent.Type.JUNCTION):
			continue
		if root_to_pins[root].size() == 1 and not pin.is_ground:
			result.warnings.append("Floating pin detected: " + pin_id)

	return result

static func get_spice_name(comp: CircuitComponent) -> String:
	var prefix = comp.get_spice_prefix()
	if comp.id.begins_with(prefix):
		return comp.id
	return prefix + comp.id

static func generate_ngspice_netlist(circuit_name: String, components: Dictionary, wires: Array) -> NetlistResult:
	var result = resolve_nets(components, wires)
	var lines: PackedStringArray = PackedStringArray()

	lines.append("* ===============================================")
	lines.append("* ProtoAI Circuit Schematic Netlist")
	lines.append("* Compatible with ngspice")
	lines.append("* Circuit: " + (circuit_name if circuit_name != "" else "Untitled"))
	lines.append("* ===============================================")
	lines.append("")

	if not result.has_ground:
		result.warnings.append("No Ground reference (0) found. Please add a Ground element for SPICE simulation.")

	# Emit components
	for comp_id in components:
		var comp: CircuitComponent = components[comp_id]
		var sp_name = get_spice_name(comp)
		match comp.type:
			CircuitComponent.Type.RESISTOR, CircuitComponent.Type.CAPACITOR, CircuitComponent.Type.INDUCTOR:
				var p1_id = comp.id + ":p1"
				var p2_id = comp.id + ":p2"
				var n1 = result.node_map.get(p1_id, "N_NC")
				var n2 = result.node_map.get(p2_id, "N_NC")
				var val = _format_spice_value(comp.value)
				lines.append("%s %s %s %s" % [sp_name, n1, n2, val])

			CircuitComponent.Type.DIODE:
				var a_id = comp.id + ":anode"
				var k_id = comp.id + ":cathode"
				var na = result.node_map.get(a_id, "N_NC")
				var nk = result.node_map.get(k_id, "N_NC")
				lines.append("%s %s %s DMOD" % [sp_name, na, nk])

			CircuitComponent.Type.BJT_NPN, CircuitComponent.Type.BJT_PNP:
				var b_id = comp.id + ":B"
				var c_id = comp.id + ":C"
				var e_id = comp.id + ":E"
				var nb = result.node_map.get(b_id, "N_NC")
				var nc = result.node_map.get(c_id, "N_NC")
				var ne = result.node_map.get(e_id, "N_NC")
				var mod = "NMOD" if comp.type == CircuitComponent.Type.BJT_NPN else "PMOD"
				lines.append("%s %s %s %s %s" % [sp_name, nc, nb, ne, mod])

			CircuitComponent.Type.OPAMP:
				var in_p_id = comp.id + ":in_pos"
				var in_n_id = comp.id + ":in_neg"
				var out_id = comp.id + ":out"
				var np = result.node_map.get(in_p_id, "N_NC")
				var nn = result.node_map.get(in_n_id, "N_NC")
				var no = result.node_map.get(out_id, "N_NC")
				lines.append("%s %s %s %s opamp_ideal" % [sp_name, np, nn, no])

			CircuitComponent.Type.VOLTAGE_SOURCE:
				var pos_id = comp.id + ":pos"
				var neg_id = comp.id + ":neg"
				var n_pos = result.node_map.get(pos_id, "N_NC")
				var n_neg = result.node_map.get(neg_id, "N_NC")
				var val = _format_spice_value(comp.value)
				if n_pos == n_neg and n_pos != "N_NC":
					result.errors.append("Voltage source %s has both terminals connected to node %s (Short Circuit!)" % [sp_name, n_pos])
				lines.append("%s %s %s DC %s" % [sp_name, n_pos, n_neg, val])

			CircuitComponent.Type.CURRENT_SOURCE:
				var pos_id = comp.id + ":pos"
				var neg_id = comp.id + ":neg"
				var n_pos = result.node_map.get(pos_id, "N_NC")
				var n_neg = result.node_map.get(neg_id, "N_NC")
				var val = _format_spice_value(comp.value)
				# SPICE convention: Ixxx N_from N_to DCVAL (current leaves N_from into N_to)
				lines.append("%s %s %s DC %s" % [sp_name, n_neg, n_pos, val])

			CircuitComponent.Type.POTENTIOMETER:
				var t1_id = comp.id + ":t1"
				var w_id = comp.id + ":wiper"
				var t2_id = comp.id + ":t2"
				var nt1 = result.node_map.get(t1_id, "N_NC")
				var nw = result.node_map.get(w_id, "N_NC")
				var nt2 = result.node_map.get(t2_id, "N_NC")
				var val = _format_spice_value(comp.value)
				lines.append("%s %s %s %s POT %s" % [sp_name, nt1, nw, nt2, val])

			CircuitComponent.Type.TRANSFORMER:
				var pp_id = comp.id + ":pri_pos"
				var pn_id = comp.id + ":pri_neg"
				var sp_id = comp.id + ":sec_pos"
				var sn_id = comp.id + ":sec_neg"
				var npp = result.node_map.get(pp_id, "N_NC")
				var npn = result.node_map.get(pn_id, "N_NC")
				var nsp = result.node_map.get(sp_id, "N_NC")
				var nsn = result.node_map.get(sn_id, "N_NC")
				lines.append("%s %s %s %s %s XFMR" % [sp_name, npp, npn, nsp, nsn])

			CircuitComponent.Type.SCR:
				var a_id = comp.id + ":anode"
				var g_id = comp.id + ":gate"
				var k_id = comp.id + ":cathode"
				var na = result.node_map.get(a_id, "N_NC")
				var ng = result.node_map.get(g_id, "N_NC")
				var nk = result.node_map.get(k_id, "N_NC")
				lines.append("%s %s %s %s %s" % [sp_name, na, ng, nk, comp.value])

			CircuitComponent.Type.TRIAC:
				var m2_id = comp.id + ":mt2"
				var g_id = comp.id + ":gate"
				var m1_id = comp.id + ":mt1"
				var nm2 = result.node_map.get(m2_id, "N_NC")
				var ng = result.node_map.get(g_id, "N_NC")
				var nm1 = result.node_map.get(m1_id, "N_NC")
				lines.append("%s %s %s %s %s" % [sp_name, nm2, ng, nm1, comp.value])

			CircuitComponent.Type.IC:
				var pin_nodes: PackedStringArray = PackedStringArray()
				for pin in comp.pins:
					var pin_id = pin.id
					var p_node = result.node_map.get(pin_id, "N_NC")
					pin_nodes.append(p_node)
				var model_name = comp.ic_data.get("model", comp.value)
				lines.append("%s %s %s" % [sp_name, " ".join(pin_nodes), model_name])

			CircuitComponent.Type.GROUND:
				var gnd_id = comp.id + ":gnd"
				var n_gnd = result.node_map.get(gnd_id, "0")
				lines.append("* Ground reference %s connected to node %s" % [comp.id, n_gnd])

			CircuitComponent.Type.NET_LABEL:
				var l_pin_id = comp.id + ":pin"
				var n_lbl = result.node_map.get(l_pin_id, comp.value)
				lines.append("* NetLabel %s (%s) connected to node %s" % [comp.id, comp.value, n_lbl])

			CircuitComponent.Type.JUNCTION:
				# Pure schematic solder dot; omit from SPICE netlist
				pass

	lines.append("")
	lines.append("* Simulation Control")
	lines.append(".control")
	lines.append("op")
	lines.append("print all")
	lines.append(".endc")
	lines.append(".end")

	result.netlist_text = "\n".join(lines)
	return result

static func _format_spice_value(val_str: String) -> String:
	var cleaned = val_str.strip_edges()
	if cleaned.is_empty():
		return "1k"
	cleaned = cleaned.trim_suffix("V").trim_suffix("v")
	cleaned = cleaned.trim_suffix("A").trim_suffix("a")
	cleaned = cleaned.trim_suffix("Ohm").trim_suffix("ohm").trim_suffix("Ω")
	cleaned = cleaned.strip_edges()
	return cleaned if cleaned != "" else "1"
