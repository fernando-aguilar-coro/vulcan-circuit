class_name CircuitIntent
extends RefCounted

## CircuitIntent: Represents a user action dispatched to the MVI store to produce a new state.

enum IntentType {
	SELECT_TOOL,
	PLACE_COMPONENT,
	MOVE_COMPONENT,
	MOVE_COMPONENTS,
	ROTATE_COMPONENT,
	START_WIRE,
	FINISH_WIRE,
	CANCEL_WIRE,
	SELECT_ELEMENT,
	SELECT_ELEMENTS,
	UPDATE_COMPONENT_VALUE,
	DELETE_ELEMENT,
	DELETE_SELECTED,
	CLEAR_CIRCUIT,
	LOAD_PRESET,
	UPDATE_MOUSE_POS,
	UPDATE_CAMERA_TRANSFORM,
	ANALYZE_IMAGE,
	SET_AI_RESULT,
	TOGGLE_AI_PANEL,
	BUILD_CIRCUIT_FROM_AI,
	RUN_SIMULATION
}

var type: IntentType
var tool_type: int = 0
var component_type: int = 0
var element_id: String = ""
var element_ids: Array = []
var is_additive: bool = false
var pin_id: String = ""
var position: Vector2 = Vector2.ZERO
var move_positions: Dictionary = {} # comp_id -> Vector2
var value_string: String = ""
var preset_name: String = ""
var pan_offset: Vector2 = Vector2.ZERO
var zoom_level: float = 1.0

# AI fields
var image_path: String = ""
var ai_text: String = ""
var ai_is_loading: bool = false
var ai_error: String = ""
var panel_visible: bool = false
var layout_mode: int = 0

static func create_select_tool(p_tool: int) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.SELECT_TOOL
	i.tool_type = p_tool
	return i

static func create_place_component(p_comp_type: int, p_pos: Vector2) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.PLACE_COMPONENT
	i.component_type = p_comp_type
	i.position = p_pos
	return i

static func create_move_component(p_id: String, p_pos: Vector2) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.MOVE_COMPONENT
	i.element_id = p_id
	i.position = p_pos
	return i

static func create_move_components(p_positions: Dictionary) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.MOVE_COMPONENTS
	i.move_positions = p_positions
	return i

static func create_rotate_component(p_id: String) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.ROTATE_COMPONENT
	i.element_id = p_id
	return i

static func create_start_wire(p_pin_id: String) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.START_WIRE
	i.pin_id = p_pin_id
	return i

static func create_finish_wire(p_pin_id: String) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.FINISH_WIRE
	i.pin_id = p_pin_id
	return i

static func create_cancel_wire() -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.CANCEL_WIRE
	return i

static func create_select_element(p_id: String, p_additive: bool = false) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.SELECT_ELEMENT
	i.element_id = p_id
	i.is_additive = p_additive
	return i

static func create_select_elements(p_ids: Array, p_additive: bool = false) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.SELECT_ELEMENTS
	i.element_ids = p_ids
	i.is_additive = p_additive
	return i

static func create_update_component_value(p_id: String, p_val: String) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.UPDATE_COMPONENT_VALUE
	i.element_id = p_id
	i.value_string = p_val
	return i

static func create_delete_element(p_id: String) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.DELETE_ELEMENT
	i.element_id = p_id
	return i

static func create_delete_selected() -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.DELETE_SELECTED
	return i

static func create_clear_circuit() -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.CLEAR_CIRCUIT
	return i

static func create_load_preset(p_name: String) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.LOAD_PRESET
	i.preset_name = p_name
	return i

static func create_update_mouse_pos(p_pos: Vector2, p_grid: Vector2) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.UPDATE_MOUSE_POS
	i.position = p_pos
	i.pan_offset = p_grid
	return i

static func create_update_camera_transform(p_pan: Vector2, p_zoom: float) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.UPDATE_CAMERA_TRANSFORM
	i.pan_offset = p_pan
	i.zoom_level = p_zoom
	return i

static func create_analyze_image(p_image_path: String) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.ANALYZE_IMAGE
	i.image_path = p_image_path
	return i

static func create_set_ai_result(p_text: String, p_loading: bool, p_error: String) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.SET_AI_RESULT
	i.ai_text = p_text
	i.ai_is_loading = p_loading
	i.ai_error = p_error
	return i

static func create_toggle_ai_panel(p_visible: bool) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.TOGGLE_AI_PANEL
	i.panel_visible = p_visible
	return i

static func create_build_circuit_from_ai(p_text: String, p_mode: int = 0) -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.BUILD_CIRCUIT_FROM_AI
	i.ai_text = p_text
	i.layout_mode = p_mode
	return i

static func create_run_simulation() -> RefCounted:
	var i = CircuitIntent.new()
	i.type = IntentType.RUN_SIMULATION
	return i
