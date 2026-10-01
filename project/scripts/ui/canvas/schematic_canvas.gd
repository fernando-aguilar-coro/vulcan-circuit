class_name SchematicCanvas
extends Control

## SchematicCanvas: Renders the schematic diagram, grid (via GPU shader), wires, components, and marquee box.

signal intent_dispatched(intent: CircuitIntent)

const COLOR_WIRE = Color(0.2, 0.85, 0.5, 1.0)
const COLOR_WIRE_PREVIEW = Color(1.0, 0.8, 0.2, 0.8)

var current_state: CircuitState = null
var camera: CanvasCamera
var input_controller: CanvasInputController
var grid_bg: ColorRect

var pan_offset: Vector2:
	get: return camera.pan_offset
	set(v):
		camera.update_pan(v)
		queue_redraw()

var zoom_level: float:
	get: return camera.zoom_level
	set(v):
		camera.zoom_level = v
		camera.update_material_params()
		queue_redraw()

var ghost_rotation_deg: int:
	get: return input_controller.ghost_rotation_deg
	set(v): input_controller.ghost_rotation_deg = v

func _init() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_PASS
	camera = CanvasCamera.new()
	input_controller = CanvasInputController.new(camera)
	input_controller.intent_dispatched.connect(func(i): intent_dispatched.emit(i))
	input_controller.redraw_requested.connect(queue_redraw)

	grid_bg = ColorRect.new()
	grid_bg.show_behind_parent = true
	grid_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid_bg.material = camera.grid_material
	add_child(grid_bg)

func set_state(state: CircuitState) -> void:
	current_state = state
	queue_redraw()

func screen_to_world(screen_pos: Vector2) -> Vector2:
	return camera.screen_to_world(screen_pos)

func world_to_screen(world_pos: Vector2) -> Vector2:
	return camera.world_to_screen(world_pos)

func snap_to_grid(world_pos: Vector2) -> Vector2:
	return camera.snap_to_grid(world_pos)

func _gui_input(event: InputEvent) -> void:
	input_controller.handle_input(event, current_state, self)

func _draw() -> void:
	if not current_state:
		return

	# 1. Camera transform
	draw_set_transform(camera.pan_offset, 0.0, Vector2(camera.zoom_level, camera.zoom_level))

	# 2. Wires
	for w in current_state.wires:
		var p1 = current_state.get_pin_world_pos(w.from_pin_id)
		var p2 = current_state.get_pin_world_pos(w.to_pin_id)
		var is_selected = current_state.is_selected(w.id)
		var wire_color = Color(0.2, 0.75, 1.0) if is_selected else COLOR_WIRE

		var pts = WireRouter.get_wire_points(p1, p2, w.waypoints)
		for i in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], wire_color, 2.5)

	# 3. Active Wire Preview (Rubber-band)
	if current_state.wire_start_pin_id != "":
		var p_start = current_state.get_pin_world_pos(current_state.wire_start_pin_id)
		var mouse_w = camera.screen_to_world(get_local_mouse_position())
		var snap_target = camera.snap_to_grid(mouse_w)
		if input_controller.hovered_pin_id != "":
			snap_target = current_state.get_pin_world_pos(input_controller.hovered_pin_id)
		draw_line(p_start, snap_target, COLOR_WIRE_PREVIEW, 2.0)
		draw_circle(snap_target, 4.0, COLOR_WIRE_PREVIEW)

	# 4. Components
	var default_font = ThemeDB.fallback_font
	for comp_id in current_state.components:
		var comp: CircuitComponent = current_state.components[comp_id]
		var is_selected = current_state.is_selected(comp.id)
		ComponentRenderer.draw_component(self, comp, is_selected, input_controller.hovered_pin_id, default_font)

	# 5. Marquee Selection Box
	if input_controller.is_box_selecting:
		var sbox = input_controller.get_selection_box_rect()
		if sbox.size.length() > 2.0:
			draw_rect(sbox, Color(0.2, 0.65, 1.0, 0.15), true)
			draw_rect(sbox, Color(0.2, 0.65, 1.0, 0.8), false, 1.5)

	# 6. Ghost Preview
	_draw_ghost_preview(default_font)

	# Reset transform
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ghost_preview(font: Font) -> void:
	if not current_state:
		return

	var tool_type = current_state.active_tool
	var comp_type: CircuitComponent.Type
	var is_ghost = true

	match tool_type:
		CircuitState.Tool.ADD_RESISTOR:
			comp_type = CircuitComponent.Type.RESISTOR
		CircuitState.Tool.ADD_VOLTAGE_SOURCE:
			comp_type = CircuitComponent.Type.VOLTAGE_SOURCE
		CircuitState.Tool.ADD_CURRENT_SOURCE:
			comp_type = CircuitComponent.Type.CURRENT_SOURCE
		CircuitState.Tool.ADD_GROUND:
			comp_type = CircuitComponent.Type.GROUND
		_:
			is_ghost = false

	if is_ghost:
		var mouse_w = camera.screen_to_world(get_local_mouse_position())
		var snap_pos = camera.snap_to_grid(mouse_w)
		var ghost = CircuitComponent.new("Ghost", comp_type, snap_pos)
		ghost.rotation_deg = input_controller.ghost_rotation_deg
		ComponentRenderer.draw_component(self, ghost, false, "", font)
