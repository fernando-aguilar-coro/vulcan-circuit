class_name CanvasInputController
extends RefCounted

## CanvasInputController: Translates UI input events into MVI intents and optimizes redraw signals.

signal intent_dispatched(intent: CircuitIntent)
signal redraw_requested()

var camera: CanvasCamera
var is_panning: bool = false
var pan_start_mouse: Vector2 = Vector2.ZERO
var pan_start_offset: Vector2 = Vector2.ZERO

var is_dragging_comp: bool = false
var drag_comps_start_positions: Dictionary = {} # comp_id -> Vector2
var drag_mouse_start_world: Vector2 = Vector2.ZERO

var is_box_selecting: bool = false
var box_start_world: Vector2 = Vector2.ZERO
var box_current_world: Vector2 = Vector2.ZERO

var hovered_pin_id: String = ""
var ghost_rotation_deg: int = 0

func _init(p_camera: CanvasCamera) -> void:
	camera = p_camera

func get_selection_box_rect() -> Rect2:
	var min_p = Vector2(minf(box_start_world.x, box_current_world.x), minf(box_start_world.y, box_current_world.y))
	var max_p = Vector2(maxf(box_start_world.x, box_current_world.x), maxf(box_start_world.y, box_current_world.y))
	return Rect2(min_p, max_p - min_p)

func handle_input(event: InputEvent, current_state: CircuitState, control: Control) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		var world_pos = camera.screen_to_world(mb.position)
		var grid_pos = camera.snap_to_grid(world_pos)

		# Pan with Middle or Right Mouse Button
		if mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_RIGHT and current_state and current_state.active_tool == CircuitState.Tool.SELECT):
			if mb.pressed:
				is_panning = true
				pan_start_mouse = mb.position
				pan_start_offset = camera.pan_offset
			else:
				is_panning = false
			control.accept_event()
			return

		# Right Click in other modes: Cancel wire or switch back to SELECT
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if current_state:
				if current_state.wire_start_pin_id != "":
					intent_dispatched.emit(CircuitIntent.create_cancel_wire())
				else:
					intent_dispatched.emit(CircuitIntent.create_select_tool(CircuitState.Tool.SELECT))
			control.accept_event()
			return

		# Zoom with Wheel
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if camera.zoom_at(mb.position, 1.15):
				redraw_requested.emit()
			control.accept_event()
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if camera.zoom_at(mb.position, 1.0 / 1.15):
				redraw_requested.emit()
			control.accept_event()
			return

		# Left Click
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_handle_left_click_pressed(mb, world_pos, grid_pos, current_state)
			else:
				_handle_left_click_released(mb, world_pos, grid_pos, current_state)
			control.accept_event()
			return

	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion
		if is_panning:
			camera.update_pan(pan_start_offset + (mm.position - pan_start_mouse))
			redraw_requested.emit()
			control.accept_event()
			return

		var world_pos = camera.screen_to_world(mm.position)
		var prev_hovered = hovered_pin_id

		if current_state:
			hovered_pin_id = current_state.find_pin_at_position(world_pos, 14.0)

		# Box selecting
		if is_box_selecting:
			box_current_world = world_pos
			redraw_requested.emit()
			control.accept_event()
			return

		# Dragging one or multiple components
		if is_dragging_comp and current_state and drag_comps_start_positions.size() > 0:
			var delta_world = world_pos - drag_mouse_start_world
			var snapped_delta = camera.snap_to_grid(delta_world)
			var moved = false
			for cid in drag_comps_start_positions:
				if current_state.components.has(cid):
					var comp = current_state.components[cid]
					var new_pos = drag_comps_start_positions[cid] + snapped_delta
					if comp.position != new_pos:
						comp.position = new_pos
						moved = true
			if moved:
				redraw_requested.emit()
			control.accept_event()
			return

		# Smart Redraw: Only queue redraw when a visual change occurs
		var need_redraw = false
		if hovered_pin_id != prev_hovered:
			need_redraw = true
		elif current_state:
			if current_state.wire_start_pin_id != "":
				need_redraw = true
			elif current_state.active_tool in [
				CircuitState.Tool.ADD_RESISTOR,
				CircuitState.Tool.ADD_VOLTAGE_SOURCE,
				CircuitState.Tool.ADD_CURRENT_SOURCE,
				CircuitState.Tool.ADD_GROUND
			]:
				need_redraw = true

		if need_redraw:
			redraw_requested.emit()

func _handle_left_click_pressed(mb: InputEventMouseButton, world_pos: Vector2, grid_pos: Vector2, current_state: CircuitState) -> void:
	if not current_state:
		return

	var pin_clicked = current_state.find_pin_at_position(world_pos, 14.0)
	var comp_clicked = current_state.find_component_at_position(world_pos, 35.0)
	var is_additive = mb.shift_pressed or mb.ctrl_pressed

	match current_state.active_tool:
		CircuitState.Tool.SELECT:
			if pin_clicked != "":
				intent_dispatched.emit(CircuitIntent.create_start_wire(pin_clicked))
			elif comp_clicked != "":
				if is_additive:
					intent_dispatched.emit(CircuitIntent.create_select_element(comp_clicked, true))
				else:
					# If already selected within a multi-selection, keep multi-selection for group drag
					if not (comp_clicked in current_state.selected_ids):
						intent_dispatched.emit(CircuitIntent.create_select_element(comp_clicked, false))

				# Prepare dragging group
				is_dragging_comp = true
				drag_mouse_start_world = world_pos
				drag_comps_start_positions.clear()

				if comp_clicked in current_state.selected_ids:
					for sid in current_state.selected_ids:
						if current_state.components.has(sid):
							drag_comps_start_positions[sid] = current_state.components[sid].position
				else:
					drag_comps_start_positions[comp_clicked] = current_state.components[comp_clicked].position
			else:
				var wire_clicked = WireRouter.find_wire_at_pos(world_pos, current_state.wires, current_state)
				if wire_clicked != "":
					intent_dispatched.emit(CircuitIntent.create_select_element(wire_clicked, is_additive))
				else:
					# Empty space: start box selection
					is_box_selecting = true
					box_start_world = world_pos
					box_current_world = world_pos

		CircuitState.Tool.WIRE:
			if pin_clicked != "":
				if current_state.wire_start_pin_id == "":
					intent_dispatched.emit(CircuitIntent.create_start_wire(pin_clicked))
				else:
					intent_dispatched.emit(CircuitIntent.create_finish_wire(pin_clicked))
			else:
				if current_state.wire_start_pin_id != "":
					intent_dispatched.emit(CircuitIntent.create_cancel_wire())

		CircuitState.Tool.ADD_RESISTOR:
			intent_dispatched.emit(CircuitIntent.create_place_component(CircuitComponent.Type.RESISTOR, grid_pos))
		CircuitState.Tool.ADD_VOLTAGE_SOURCE:
			intent_dispatched.emit(CircuitIntent.create_place_component(CircuitComponent.Type.VOLTAGE_SOURCE, grid_pos))
		CircuitState.Tool.ADD_CURRENT_SOURCE:
			intent_dispatched.emit(CircuitIntent.create_place_component(CircuitComponent.Type.CURRENT_SOURCE, grid_pos))
		CircuitState.Tool.ADD_GROUND:
			intent_dispatched.emit(CircuitIntent.create_place_component(CircuitComponent.Type.GROUND, grid_pos))

		CircuitState.Tool.DELETE:
			if comp_clicked != "":
				intent_dispatched.emit(CircuitIntent.create_delete_element(comp_clicked))
			else:
				var wire_clicked = WireRouter.find_wire_at_pos(world_pos, current_state.wires, current_state)
				if wire_clicked != "":
					intent_dispatched.emit(CircuitIntent.create_delete_element(wire_clicked))

func _handle_left_click_released(mb: InputEventMouseButton, world_pos: Vector2, _grid_pos: Vector2, current_state: CircuitState) -> void:
	if is_box_selecting:
		is_box_selecting = false
		var sbox = get_selection_box_rect()
		var is_additive = mb.shift_pressed or mb.ctrl_pressed

		if sbox.size.length() > 6.0 and current_state:
			var found_comps = current_state.find_components_in_rect(sbox)
			var found_wires = current_state.find_wires_in_rect(sbox)
			var total_found: Array[String] = []
			total_found.append_array(found_comps)
			total_found.append_array(found_wires)
			intent_dispatched.emit(CircuitIntent.create_select_elements(total_found, is_additive))
		else:
			if not is_additive:
				intent_dispatched.emit(CircuitIntent.create_select_element(""))
		redraw_requested.emit()

	if is_dragging_comp:
		is_dragging_comp = false
		if current_state and drag_comps_start_positions.size() > 0:
			var final_positions: Dictionary = {}
			for cid in drag_comps_start_positions:
				if current_state.components.has(cid):
					final_positions[cid] = current_state.components[cid].position
			intent_dispatched.emit(CircuitIntent.create_move_components(final_positions))
		drag_comps_start_positions.clear()

	if current_state and current_state.wire_start_pin_id != "" and current_state.active_tool == CircuitState.Tool.SELECT:
		var pin_released = current_state.find_pin_at_position(world_pos, 14.0)
		if pin_released != "" and pin_released != current_state.wire_start_pin_id:
			intent_dispatched.emit(CircuitIntent.create_finish_wire(pin_released))
		else:
			intent_dispatched.emit(CircuitIntent.create_cancel_wire())
