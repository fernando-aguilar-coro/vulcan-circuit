class_name MainEditor
extends Control



const WorkbenchPanelClass = preload("res://scripts/ui/panels/workbench_panel.gd")

var store: CircuitStore
var canvas: SchematicCanvas
var toolbar: ToolbarPanel
var inspector: InspectorPanel
var workbench: WorkbenchPanelClass
var gemini_service: GeminiService

func _ready() -> void:
	# Initialize Gemini Service
	gemini_service = GeminiService.new()
	add_child(gemini_service)
	gemini_service.request_completed.connect(_on_ai_request_completed)
	gemini_service.request_failed.connect(_on_ai_request_failed)

	# Build layout dynamically
	_build_ui_hierarchy()

	# Initialize MVI Store
	store = CircuitStore.new()
	store.state_changed.connect(_render_state)

	# Initial render
	_render_state(store.get_state())

	# Load initial voltage divider sample to give an immediate working circuit
	store.dispatch(CircuitIntent.create_load_preset("VoltageDivider"))

func _build_ui_hierarchy() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var root_vbox = VBoxContainer.new()
	root_vbox.anchor_right = 1.0
	root_vbox.anchor_bottom = 1.0
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	# 1. Top Toolbar
	toolbar = ToolbarPanel.new()
	toolbar.intent_dispatched.connect(_on_intent_dispatched)
	root_vbox.add_child(toolbar)

	# 2. Main Work Area (VSplitContainer with Work Area on top, Bottom Panels on bottom)
	var v_split = VSplitContainer.new()
	v_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v_split.split_offset = 430
	root_vbox.add_child(v_split)

	# 2a. Center + Right Inspector Area (HSplitContainer)
	var h_split = HSplitContainer.new()
	h_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h_split.split_offset = 800
	v_split.add_child(h_split)

	# Canvas in Center
	canvas = SchematicCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.intent_dispatched.connect(_on_intent_dispatched)
	h_split.add_child(canvas)

	# Inspector on Right
	inspector = InspectorPanel.new()
	inspector.intent_dispatched.connect(_on_intent_dispatched)
	h_split.add_child(inspector)

	# 2b. Bottom Section: Workbench Dock (Reconstructor, Simulation, SPICE Terminal)
	workbench = WorkbenchPanelClass.new()
	workbench.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workbench.intent_dispatched.connect(_on_intent_dispatched)
	v_split.add_child(workbench)

func _render_state(new_state: CircuitState) -> void:
	canvas.set_state(new_state)
	toolbar.update_active_tool(new_state.active_tool)
	inspector.update_selection(new_state)
	workbench.update_state(new_state)

func _on_intent_dispatched(intent: CircuitIntent) -> void:
	if intent.type == CircuitIntent.IntentType.ANALYZE_IMAGE:
		gemini_service.analyze_image(intent.image_path)
	store.dispatch(intent)

func _on_ai_request_completed(result_text: String) -> void:
	store.dispatch(CircuitIntent.create_set_ai_result(result_text, false, ""))

func _on_ai_request_failed(err_msg: String) -> void:
	store.dispatch(CircuitIntent.create_set_ai_result("", false, err_msg))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	# If a text edit has focus, ignore global shortcuts
	var focused = get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return

	match event.keycode:
		KEY_S:
			store.dispatch(CircuitIntent.create_select_tool(CircuitState.Tool.SELECT))
		KEY_W:
			store.dispatch(CircuitIntent.create_select_tool(CircuitState.Tool.WIRE))
		KEY_R:
			var current_state = store.get_state()
			if not current_state.selected_ids.is_empty():
				store.dispatch(CircuitIntent.create_rotate_component(current_state.selected_id))
			elif current_state.active_tool == CircuitState.Tool.ADD_RESISTOR:
				canvas.ghost_rotation_deg = (canvas.ghost_rotation_deg + 90) % 360
				canvas.queue_redraw()
			else:
				store.dispatch(CircuitIntent.create_select_tool(CircuitState.Tool.ADD_RESISTOR))
		KEY_V:
			store.dispatch(CircuitIntent.create_select_tool(CircuitState.Tool.ADD_VOLTAGE_SOURCE))
		KEY_I:
			store.dispatch(CircuitIntent.create_select_tool(CircuitState.Tool.ADD_CURRENT_SOURCE))
		KEY_G:
			store.dispatch(CircuitIntent.create_select_tool(CircuitState.Tool.ADD_GROUND))
		KEY_DELETE, KEY_BACKSPACE:
			store.dispatch(CircuitIntent.create_delete_selected())
		KEY_ESCAPE:
			var current_state = store.get_state()
			if current_state.wire_start_pin_id != "":
				store.dispatch(CircuitIntent.create_cancel_wire())
			else:
				store.dispatch(CircuitIntent.create_select_tool(CircuitState.Tool.SELECT))
