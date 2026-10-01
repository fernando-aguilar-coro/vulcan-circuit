class_name CircuitState
extends RefCounted

## CircuitState: Immutable snapshot of the entire schematic editor state (MVI Model).

enum Tool {
	SELECT,
	WIRE,
	ADD_RESISTOR,
	ADD_VOLTAGE_SOURCE,
	ADD_CURRENT_SOURCE,
	ADD_GROUND,
	DELETE
}

var components: Dictionary = {} # comp_id -> CircuitComponent
var wires: Array = [] # Array of CircuitWire
var selected_ids: Array = [] # Multi-selection support

var selected_id: String:
	get: return selected_ids[0] if selected_ids.size() > 0 else ""
	set(v):
		if v == "":
			selected_ids.clear()
		else:
			selected_ids = [v]

var active_tool: Tool = Tool.SELECT
var wire_start_pin_id: String = ""
var mouse_world_pos: Vector2 = Vector2.ZERO
var mouse_grid_pos: Vector2 = Vector2.ZERO
var pan_offset: Vector2 = Vector2.ZERO
var zoom_level: float = 1.0

var netlist_text: String = ""
var warnings: Array[String] = []
var errors: Array[String] = []
var has_ground: bool = false

var comp_counters: Dictionary = {
	CircuitComponent.Type.RESISTOR: 1,
	CircuitComponent.Type.VOLTAGE_SOURCE: 1,
	CircuitComponent.Type.CURRENT_SOURCE: 1,
	CircuitComponent.Type.GROUND: 1,
	CircuitComponent.Type.NET_LABEL: 1
}

# AI Assistant state
var ai_response_text: String = ""
var ai_is_loading: bool = false
var ai_error: String = ""
var ai_image_path: String = ""
var ai_panel_visible: bool = false

# ngspice Simulation State
var sim_is_running: bool = false
var sim_results: Dictionary = {}
var sim_node_voltages: Dictionary = {}
var sim_branch_currents: Dictionary = {}
var sim_log: String = ""
var sim_error: String = ""

func is_selected(id: String) -> bool:
	return id in selected_ids

func get_selected_component() -> CircuitComponent:
	if selected_ids.size() > 0 and components.has(selected_ids[0]):
		return components[selected_ids[0]]
	return null

func get_selected_components() -> Array:
	var result: Array = []
	for sid in selected_ids:
		if components.has(sid):
			result.append(components[sid])
	return result

func get_pin_world_pos(pin_id: String) -> Vector2:
	var parts = pin_id.split(":")
	if parts.size() == 2:
		var comp_id = parts[0]
		var pin_name = parts[1]
		if components.has(comp_id):
			return components[comp_id].get_pin_world_position(pin_name)
	return Vector2.ZERO

func find_pin_at_position(pos: Vector2, radius: float = 15.0) -> String:
	for comp_id in components:
		var comp: CircuitComponent = components[comp_id]
		if comp.is_virtual:
			continue
		for pin in comp.pins:
			var pin_world = pin.get_world_position(comp.position, comp.rotation_deg)
			if pos.distance_to(pin_world) <= radius:
				return pin.id
	return ""

func find_component_at_position(pos: Vector2, radius: float = 35.0) -> String:
	for comp_id in components:
		var comp: CircuitComponent = components[comp_id]
		if comp.is_virtual:
			continue
		if pos.distance_to(comp.position) <= radius:
			return comp_id
	return ""

func find_components_in_rect(rect: Rect2) -> Array:
	var found: Array = []
	for comp_id in components:
		var comp: CircuitComponent = components[comp_id]
		if comp.is_virtual:
			continue
		var bounds_size = Vector2(70, 90)
		if comp.type == CircuitComponent.Type.IC:
			bounds_size = comp.ic_box_size + Vector2(24, 24)
		elif comp.type == CircuitComponent.Type.RESISTOR or comp.type == CircuitComponent.Type.POTENTIOMETER:
			bounds_size = Vector2(90, 60)
		var comp_rect = Rect2(comp.position - bounds_size / 2.0, bounds_size)
		if rect.encloses(comp_rect) or rect.intersects(comp_rect) or rect.has_point(comp.position):
			found.append(comp_id)
	return found

func find_wires_in_rect(rect: Rect2) -> Array:
	var found: Array = []
	for w in wires:
		var p1 = get_pin_world_pos(w.from_pin_id)
		var p2 = get_pin_world_pos(w.to_pin_id)
		if rect.has_point(p1) and rect.has_point(p2):
			found.append(w.id)
	return found

func clone() -> RefCounted:
	var s = get_script().new()
	for k in components:
		s.components[k] = components[k].clone()
	for w in wires:
		s.wires.append(w.clone())
	s.selected_ids = selected_ids.duplicate()
	s.active_tool = active_tool
	s.wire_start_pin_id = wire_start_pin_id
	s.mouse_world_pos = mouse_world_pos
	s.mouse_grid_pos = mouse_grid_pos
	s.pan_offset = pan_offset
	s.zoom_level = zoom_level
	s.netlist_text = netlist_text
	s.warnings = warnings.duplicate()
	s.errors = errors.duplicate()
	s.has_ground = has_ground
	s.comp_counters = comp_counters.duplicate()
	s.ai_response_text = ai_response_text
	s.ai_is_loading = ai_is_loading
	s.ai_error = ai_error
	s.ai_image_path = ai_image_path
	s.ai_panel_visible = ai_panel_visible
	s.sim_is_running = sim_is_running
	s.sim_results = sim_results.duplicate(true)
	s.sim_node_voltages = sim_node_voltages.duplicate()
	s.sim_branch_currents = sim_branch_currents.duplicate()
	s.sim_log = sim_log
	s.sim_error = sim_error
	return s
