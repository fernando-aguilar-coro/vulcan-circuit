class_name CircuitStore
extends RefCounted

## CircuitStore: The Single Source of Truth in MVI architecture. Receives intents and emits state.

signal state_changed(new_state: CircuitState)

var state: CircuitState
var simulator: RefCounted = null

func _init() -> void:
	state = CircuitState.new()
	if ClassDB.class_exists("CircuitSimulator"):
		simulator = ClassDB.instantiate("CircuitSimulator")
		simulator.init_simulator("")
	_recalculate_netlist()

func get_state() -> CircuitState:
	return state

func dispatch(intent: CircuitIntent) -> void:
	var next_state = state.clone()
	var structure_changed = false

	match intent.type:
		CircuitIntent.IntentType.SELECT_TOOL:
			next_state.active_tool = intent.tool_type as CircuitState.Tool
			next_state.wire_start_pin_id = ""

		CircuitIntent.IntentType.PLACE_COMPONENT:
			var comp_type = intent.component_type as CircuitComponent.Type
			var prefix = _get_type_prefix(comp_type)
			var counter = next_state.comp_counters.get(comp_type, 1)
			var comp_id = prefix + str(counter)
			next_state.comp_counters[comp_type] = counter + 1

			var new_comp = CircuitComponent.new(comp_id, comp_type, intent.position)
			next_state.components[comp_id] = new_comp
			next_state.selected_ids = [comp_id]
			structure_changed = true

		CircuitIntent.IntentType.MOVE_COMPONENT:
			if next_state.components.has(intent.element_id):
				next_state.components[intent.element_id].position = intent.position
				structure_changed = true

		CircuitIntent.IntentType.MOVE_COMPONENTS:
			for comp_id in intent.move_positions:
				if next_state.components.has(comp_id):
					next_state.components[comp_id].position = intent.move_positions[comp_id]
					structure_changed = true

		CircuitIntent.IntentType.ROTATE_COMPONENT:
			if intent.element_id != "" and next_state.components.has(intent.element_id):
				var comp: CircuitComponent = next_state.components[intent.element_id]
				comp.rotation_deg = (comp.rotation_deg + 90) % 360
				structure_changed = true
			elif next_state.selected_ids.size() > 0:
				for sid in next_state.selected_ids:
					if next_state.components.has(sid):
						var comp: CircuitComponent = next_state.components[sid]
						comp.rotation_deg = (comp.rotation_deg + 90) % 360
						structure_changed = true

		CircuitIntent.IntentType.START_WIRE:
			next_state.wire_start_pin_id = intent.pin_id

		CircuitIntent.IntentType.FINISH_WIRE:
			var start_pin = next_state.wire_start_pin_id
			var end_pin = intent.pin_id
			if start_pin != "" and end_pin != "" and start_pin != end_pin:
				if not _wire_exists(next_state.wires, start_pin, end_pin):
					var wire_id = "w_" + str(next_state.wires.size() + 1)
					var wire = CircuitWire.new(wire_id, start_pin, end_pin)
					next_state.wires.append(wire)
					structure_changed = true
			next_state.wire_start_pin_id = ""

		CircuitIntent.IntentType.CANCEL_WIRE:
			next_state.wire_start_pin_id = ""

		CircuitIntent.IntentType.SELECT_ELEMENT:
			if intent.is_additive:
				if intent.element_id != "":
					if intent.element_id in next_state.selected_ids:
						next_state.selected_ids.erase(intent.element_id)
					else:
						next_state.selected_ids.append(intent.element_id)
			else:
				if intent.element_id == "":
					next_state.selected_ids.clear()
				else:
					next_state.selected_ids = [intent.element_id]

		CircuitIntent.IntentType.SELECT_ELEMENTS:
			if intent.is_additive:
				for id in intent.element_ids:
					if not id in next_state.selected_ids:
						next_state.selected_ids.append(id)
			else:
				next_state.selected_ids = intent.element_ids.duplicate()

		CircuitIntent.IntentType.UPDATE_COMPONENT_VALUE:
			if next_state.components.has(intent.element_id):
				next_state.components[intent.element_id].value = intent.value_string
				structure_changed = true

		CircuitIntent.IntentType.DELETE_ELEMENT:
			_delete_element_internal(next_state, intent.element_id)
			structure_changed = true

		CircuitIntent.IntentType.DELETE_SELECTED:
			var to_delete = next_state.selected_ids.duplicate()
			for id in to_delete:
				_delete_element_internal(next_state, id)
			next_state.selected_ids.clear()
			structure_changed = true

		CircuitIntent.IntentType.CLEAR_CIRCUIT:
			next_state.components.clear()
			next_state.wires.clear()
			next_state.selected_ids.clear()
			next_state.wire_start_pin_id = ""
			next_state.comp_counters = {
				CircuitComponent.Type.RESISTOR: 1,
				CircuitComponent.Type.VOLTAGE_SOURCE: 1,
				CircuitComponent.Type.CURRENT_SOURCE: 1,
				CircuitComponent.Type.GROUND: 1,
				CircuitComponent.Type.NET_LABEL: 1
			}
			structure_changed = true

		CircuitIntent.IntentType.LOAD_PRESET:
			_load_preset_internal(next_state, intent.preset_name)
			structure_changed = true

		CircuitIntent.IntentType.UPDATE_MOUSE_POS:
			next_state.mouse_world_pos = intent.position
			next_state.mouse_grid_pos = intent.pan_offset

		CircuitIntent.IntentType.UPDATE_CAMERA_TRANSFORM:
			next_state.pan_offset = intent.pan_offset
			next_state.zoom_level = intent.zoom_level

		CircuitIntent.IntentType.ANALYZE_IMAGE:
			next_state.ai_image_path = intent.image_path
			next_state.ai_is_loading = true
			next_state.ai_error = ""
			next_state.ai_panel_visible = true

		CircuitIntent.IntentType.SET_AI_RESULT:
			next_state.ai_response_text = intent.ai_text
			next_state.ai_is_loading = intent.ai_is_loading
			next_state.ai_error = intent.ai_error
			next_state.ai_panel_visible = true
			if not intent.ai_is_loading and intent.ai_error == "" and intent.ai_text != "":
				var res = CircuitReconstructor.parse_and_build(intent.ai_text)
				if res.success:
					next_state.components = res.components
					next_state.wires = res.wires
					next_state.selected_ids.clear()
					next_state.wire_start_pin_id = ""
					structure_changed = true

		CircuitIntent.IntentType.TOGGLE_AI_PANEL:
			next_state.ai_panel_visible = intent.panel_visible

		CircuitIntent.IntentType.BUILD_CIRCUIT_FROM_AI:
			var res = CircuitReconstructor.parse_and_build(intent.ai_text)
			if res.success:
				next_state.components = res.components
				next_state.wires = res.wires
				next_state.selected_ids.clear()
				next_state.wire_start_pin_id = ""
				structure_changed = true

		CircuitIntent.IntentType.RUN_SIMULATION:
			if simulator != null and simulator.is_available():
				var netlist = next_state.netlist_text
				var sim_res = simulator.simulate_netlist(netlist)
				if sim_res.get("success", false):
					next_state.sim_results = sim_res
					next_state.sim_node_voltages = sim_res.get("node_voltages", {})
					next_state.sim_branch_currents = sim_res.get("branch_currents", {})
					next_state.sim_log = sim_res.get("log", "")
					next_state.sim_error = ""
					next_state.sim_report = _generate_op_report(next_state, sim_res)
					next_state.terminal_log += "\n[Simulation .op completed successfully]\n"
				else:
					next_state.sim_error = sim_res.get("error", "Simulation error.")
					next_state.sim_log = sim_res.get("log", "")
					next_state.sim_report = "❌ Simulation error:\n" + next_state.sim_error + "\n\nLog:\n" + next_state.sim_log
					next_state.terminal_log += "\n[Simulation error: " + next_state.sim_error + "]\n"
			else:
				next_state.sim_error = "CircuitSimulator GDExtension is not loaded or ngspice DLL unavailable."
				next_state.sim_report = next_state.sim_error

		CircuitIntent.IntentType.EXECUTE_SPICE_COMMAND:
			var cmd = intent.value_string.strip_edges()
			if not cmd.is_empty():
				if simulator != null and simulator.is_available():
					var cmd_res = simulator.execute_command(cmd)
					var out_text = cmd_res.get("log", "")
					if out_text.strip_edges().is_empty():
						out_text = "(Command executed, no output)\n"
					next_state.terminal_log += "\n> " + cmd + "\n" + out_text
				else:
					next_state.terminal_log += "\n> " + cmd + "\nError: Simulator not available.\n"

	if structure_changed:
		WireRouter.route_all_wires_with_libavoid(next_state.components, next_state.wires)
		var result = CircuitGraph.generate_ngspice_netlist("ProtoAI_Circuit", next_state.components, next_state.wires)
		next_state.netlist_text = result.netlist_text
		next_state.node_map = result.node_map
		next_state.warnings = result.warnings
		next_state.errors = result.errors
		next_state.has_ground = result.has_ground

	state = next_state
	state_changed.emit(state)

func _delete_element_internal(s: CircuitState, elem_id: String) -> void:
	if s.components.has(elem_id):
		s.components.erase(elem_id)
		# Delete all wires connected to any pin of this component
		var remaining_wires: Array = []
		for w in s.wires:
			var from_comp = w.from_pin_id.split(":")[0]
			var to_comp = w.to_pin_id.split(":")[0]
			if from_comp != elem_id and to_comp != elem_id:
				remaining_wires.append(w)
			else:
				s.selected_ids.erase(w.id)
		s.wires = remaining_wires
		s.selected_ids.erase(elem_id)
	else:
		# Check if it's a wire ID
		var remaining_wires: Array = []
		for w in s.wires:
			if w.id != elem_id:
				remaining_wires.append(w)
		s.wires = remaining_wires
		s.selected_ids.erase(elem_id)

func _wire_exists(wires: Array, p1: String, p2: String) -> bool:
	for w in wires:
		if (w.from_pin_id == p1 and w.to_pin_id == p2) or (w.from_pin_id == p2 and w.to_pin_id == p1):
			return true
	return false

func _get_type_prefix(comp_type: CircuitComponent.Type) -> String:
	match comp_type:
		CircuitComponent.Type.RESISTOR: return "R"
		CircuitComponent.Type.VOLTAGE_SOURCE: return "V"
		CircuitComponent.Type.CURRENT_SOURCE: return "I"
		CircuitComponent.Type.GROUND: return "GND"
		CircuitComponent.Type.NET_LABEL: return "LBL"
	return "X"

func _recalculate_netlist() -> void:
	var result = CircuitGraph.generate_ngspice_netlist("ProtoAI_Circuit", state.components, state.wires)
	state.netlist_text = result.netlist_text
	state.node_map = result.node_map
	state.warnings = result.warnings
	state.errors = result.errors
	state.has_ground = result.has_ground

func _load_preset_internal(s: CircuitState, _preset_name: String) -> void:
	s.components.clear()
	s.wires.clear()
	s.selected_ids.clear()
	s.wire_start_pin_id = ""
	s.comp_counters = {
		CircuitComponent.Type.RESISTOR: 3,
		CircuitComponent.Type.VOLTAGE_SOURCE: 2,
		CircuitComponent.Type.CURRENT_SOURCE: 1,
		CircuitComponent.Type.GROUND: 2
	}

	# Voltage Divider Preset:
	# V1 at (200, 300)
	var v1 = CircuitComponent.new("V1", CircuitComponent.Type.VOLTAGE_SOURCE, Vector2(200, 300), "12")
	# R1 at (350, 200) - horizontal
	var r1 = CircuitComponent.new("R1", CircuitComponent.Type.RESISTOR, Vector2(350, 200), "10k")
	# R2 at (500, 300) - vertical
	var r2 = CircuitComponent.new("R2", CircuitComponent.Type.RESISTOR, Vector2(500, 300), "4.7k")
	r2.rotation_deg = 90
	# GND1 at (200, 420)
	var gnd1 = CircuitComponent.new("GND1", CircuitComponent.Type.GROUND, Vector2(200, 420), "0")

	s.components[v1.id] = v1
	s.components[r1.id] = r1
	s.components[r2.id] = r2
	s.components[gnd1.id] = gnd1

	# Connect:
	# V1:pos (200, 260) -> R1:p1 (310, 200)
	s.wires.append(CircuitWire.new("w1", "V1:pos", "R1:p1"))
	# R1:p2 (390, 200) -> R2:p1 (500, 260)
	s.wires.append(CircuitWire.new("w2", "R1:p2", "R2:p1"))
	# R2:p2 (500, 340) -> V1:neg (200, 340)
	s.wires.append(CircuitWire.new("w3", "R2:p2", "V1:neg"))
	# V1:neg -> GND1:gnd (200, 400)
	s.wires.append(CircuitWire.new("w4", "V1:neg", "GND1:gnd"))

func _generate_op_report(s: CircuitState, sim_res: Dictionary) -> String:
	var out = "=== SPICE Operating Point (.op) Results ===\n\n"
	var node_voltages: Dictionary = sim_res.get("node_voltages", {}).duplicate()
	var all_vecs: Dictionary = sim_res.get("all_vectors", {})

	# If node_voltages is empty, extract all node vectors from all_vecs
	for k in all_vecs:
		var ks = str(k).to_lower()
		if not ks.contains("#branch"):
			var clean_node = ks
			if clean_node.begins_with("v(") and clean_node.ends_with(")"):
				clean_node = clean_node.substr(2, clean_node.length() - 3)
			if typeof(all_vecs[k]) == TYPE_FLOAT or typeof(all_vecs[k]) == TYPE_INT:
				node_voltages[clean_node] = float(all_vecs[k])

	# 1. Node Voltages
	out += "--- [Node Voltages] ---\n"
	if node_voltages.is_empty():
		out += "No node voltages recorded.\n"
	else:
		var keys = node_voltages.keys()
		keys.sort()
		for k in keys:
			var v = float(node_voltages[k])
			out += "• Node %s : %s\n" % [str(k), _format_si(v, "V")]

	# 2. Components V, I, P
	out += "\n--- [Components: Voltage (V), Current (I), Power (P)] ---\n"
	for comp_id in s.components:
		var comp: CircuitComponent = s.components[comp_id]
		if comp.type == CircuitComponent.Type.GROUND or comp.type == CircuitComponent.Type.JUNCTION or comp.type == CircuitComponent.Type.NET_LABEL:
			continue

		match comp.type:
			CircuitComponent.Type.RESISTOR:
				var n1 = s.node_map.get(comp.id + ":p1", "")
				var n2 = s.node_map.get(comp.id + ":p2", "")
				var v1 = _get_node_voltage(node_voltages, all_vecs, n1)
				var v2 = _get_node_voltage(node_voltages, all_vecs, n2)
				var v_drop = abs(v1 - v2)
				var r_val = _parse_si_value(comp.value)
				var curr = (v_drop / r_val) if r_val > 0.0 else 0.0
				var pwr = v_drop * curr
				out += "• %s [%s] (Nodes %s <-> %s):\n    ΔV = %s  |  I = %s  |  P = %s\n" % [
					comp.id, comp.value, n1, n2,
					_format_si(v_drop, "V"), _format_si(curr, "A"), _format_si(pwr, "W")
				]

			CircuitComponent.Type.VOLTAGE_SOURCE:
				var n_pos = s.node_map.get(comp.id + ":pos", "")
				var n_neg = s.node_map.get(comp.id + ":neg", "")
				var v_pos = _get_node_voltage(node_voltages, all_vecs, n_pos)
				var v_neg = _get_node_voltage(node_voltages, all_vecs, n_neg)
				var v_src = v_pos - v_neg
				# If V_src is 0 from nodes, fallback to parsed source value
				if abs(v_src) < 1e-9:
					v_src = _parse_si_value(comp.value)
				# Look for branch current in all_vectors
				var b_curr = 0.0
				var branch_key = comp.id.to_lower() + "#branch"
				if all_vecs.has(branch_key):
					b_curr = abs(float(all_vecs[branch_key]))
				var pwr = abs(v_src) * b_curr
				out += "• %s [%s] (Nodes %s -> %s):\n    V = %s  |  I_branch = %s  |  P = %s\n" % [
					comp.id, comp.value, n_pos, n_neg,
					_format_si(v_src, "V"), _format_si(b_curr, "A"), _format_si(pwr, "W")
				]

			CircuitComponent.Type.CURRENT_SOURCE:
				var n_pos = s.node_map.get(comp.id + ":pos", "")
				var n_neg = s.node_map.get(comp.id + ":neg", "")
				var v_pos = _get_node_voltage(node_voltages, all_vecs, n_pos)
				var v_neg = _get_node_voltage(node_voltages, all_vecs, n_neg)
				var v_drop = abs(v_pos - v_neg)
				var i_src = _parse_si_value(comp.value)
				var pwr = v_drop * i_src
				out += "• %s [%s] (Nodes %s -> %s):\n    ΔV = %s  |  I = %s  |  P = %s\n" % [
					comp.id, comp.value, n_pos, n_neg,
					_format_si(v_drop, "V"), _format_si(i_src, "A"), _format_si(pwr, "W")
				]

			_:
				out += "• %s [%s] (Type: %s)\n" % [comp.id, comp.value, str(comp.type)]

	return out

func _get_node_voltage(voltages: Dictionary, all_vecs: Dictionary, node_name: String) -> float:
	var clean = node_name.strip_edges().to_lower()
	if clean == "0" or clean == "gnd":
		return 0.0
	if voltages.has(clean):
		return float(voltages[clean])
	if all_vecs.has(clean):
		return float(all_vecs[clean])
	if all_vecs.has("v(" + clean + ")"):
		return float(all_vecs["v(" + clean + ")"])
	var no_plus = clean.trim_prefix("+")
	if voltages.has(no_plus):
		return float(voltages[no_plus])
	if all_vecs.has(no_plus):
		return float(all_vecs[no_plus])
	if all_vecs.has("v(" + no_plus + ")"):
		return float(all_vecs["v(" + no_plus + ")"])
	if clean.begins_with("n") and voltages.has(clean.substr(1)):
		return float(voltages[clean.substr(1)])
	return 0.0

func _parse_si_value(val_str: String) -> float:
	var s = val_str.strip_edges().to_lower().trim_suffix("v").trim_suffix("a").trim_suffix("hz").trim_suffix("ohm").trim_suffix("ω")
	var mult = 1.0
	if s.ends_with("k"):
		mult = 1e3
		s = s.substr(0, s.length() - 1)
	elif s.ends_with("meg"):
		mult = 1e6
		s = s.substr(0, s.length() - 3)
	elif s.ends_with("m") and val_str.contains("M"):
		mult = 1e6
		s = s.substr(0, s.length() - 1)
	elif s.ends_with("m"):
		mult = 1e-3
		s = s.substr(0, s.length() - 1)
	elif s.ends_with("u") or s.ends_with("µ"):
		mult = 1e-6
		s = s.substr(0, s.length() - 1)
	elif s.ends_with("n"):
		mult = 1e-9
		s = s.substr(0, s.length() - 1)
	elif s.ends_with("p"):
		mult = 1e-12
		s = s.substr(0, s.length() - 1)
	return s.to_float() * mult

func _format_si(val: float, unit: String) -> String:
	var abs_val = abs(val)
	var sign_str = "-" if val < 0.0 else ""
	if abs_val >= 1e6:
		return "%s%.3f M%s" % [sign_str, abs_val / 1e6, unit]
	elif abs_val >= 1e3:
		return "%s%.3f k%s" % [sign_str, abs_val / 1e3, unit]
	elif abs_val >= 1.0:
		return "%s%.3f %s" % [sign_str, abs_val, unit]
	elif abs_val >= 1e-3:
		return "%s%.3f m%s" % [sign_str, abs_val * 1e3, unit]
	elif abs_val >= 1e-6:
		return "%s%.3f µ%s" % [sign_str, abs_val * 1e6, unit]
	elif abs_val >= 1e-9:
		return "%s%.3f n%s" % [sign_str, abs_val * 1e9, unit]
	elif abs_val == 0.0:
		return "0.000 %s" % unit
	else:
		return "%s%.3e %s" % [sign_str, abs_val, unit]
