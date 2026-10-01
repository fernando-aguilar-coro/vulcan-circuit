class_name InspectorPanel
extends PanelContainer

## InspectorPanel: Displays properties of the selected component(s) or wire(s).

signal intent_dispatched(intent: CircuitIntent)

var lbl_title: Label
var lbl_id: Label
var lbl_pos: Label
var hbox_val: HBoxContainer
var edit_val: LineEdit
var btn_rotate: Button
var btn_delete: Button
var lbl_empty: Label

var current_selected_id: String = ""

func _init() -> void:
	custom_minimum_size = Vector2(240, 0)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18, 1.0)
	style.border_width_left = 1
	style.border_color = Color(0.2, 0.23, 0.3, 1.0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)

func _ready() -> void:
	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 10)
	add_child(content_vbox)

	var header = Label.new()
	header.text = "PROPERTIES"
	header.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	header.add_theme_font_size_override("font_size", 11)
	content_vbox.add_child(header)

	lbl_empty = Label.new()
	lbl_empty.text = "No element selected.\nClick or drag a box over elements to select."
	lbl_empty.add_theme_color_override("font_color", Color(0.4, 0.45, 0.55))
	lbl_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_vbox.add_child(lbl_empty)

	lbl_title = Label.new()
	lbl_title.add_theme_font_size_override("font_size", 16)
	lbl_title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	content_vbox.add_child(lbl_title)

	lbl_id = Label.new()
	lbl_id.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	content_vbox.add_child(lbl_id)

	lbl_pos = Label.new()
	lbl_pos.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	lbl_pos.add_theme_font_size_override("font_size", 12)
	content_vbox.add_child(lbl_pos)

	hbox_val = HBoxContainer.new()
	var lbl_v = Label.new()
	lbl_v.text = "Value:"
	lbl_v.custom_minimum_size = Vector2(50, 0)
	hbox_val.add_child(lbl_v)
	edit_val = LineEdit.new()
	edit_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_val.text_submitted.connect(_on_value_submitted)
	edit_val.focus_exited.connect(_on_value_focus_exited)
	hbox_val.add_child(edit_val)
	content_vbox.add_child(hbox_val)

	btn_rotate = Button.new()
	btn_rotate.text = "🔄 Rotate (90°)"
	btn_rotate.pressed.connect(_on_rotate_pressed)
	content_vbox.add_child(btn_rotate)

	btn_delete = Button.new()
	btn_delete.text = "🗑 Delete Selected"
	btn_delete.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	btn_delete.pressed.connect(_on_delete_pressed)
	content_vbox.add_child(btn_delete)

	_show_empty()

func update_selection(state: CircuitState) -> void:
	if not state or state.selected_ids.is_empty():
		current_selected_id = ""
		_show_empty()
		return

	if state.selected_ids.size() > 1:
		current_selected_id = ""
		lbl_empty.visible = false
		lbl_title.visible = true
		lbl_title.text = "Multiple Selection"
		lbl_id.visible = true
		var comp_count = 0
		var wire_count = 0
		for sid in state.selected_ids:
			if state.components.has(sid):
				comp_count += 1
			else:
				wire_count += 1
		lbl_id.text = "%d Components, %d Wires" % [comp_count, wire_count]
		lbl_pos.visible = true
		lbl_pos.text = "Total Selected: %d" % state.selected_ids.size()
		hbox_val.visible = false
		btn_rotate.visible = (comp_count > 0)
		btn_delete.visible = true
		return

	current_selected_id = state.selected_ids[0]
	if state.components.has(current_selected_id):
		var comp: CircuitComponent = state.components[current_selected_id]
		lbl_empty.visible = false
		lbl_title.visible = true
		lbl_title.text = _get_comp_type_name(comp.type)
		lbl_id.visible = true
		lbl_id.text = "ID: " + comp.id
		lbl_pos.visible = true
		lbl_pos.text = "Position: (%.0f, %.0f) | Rot: %d°" % [comp.position.x, comp.position.y, comp.rotation_deg]

		if comp.type != CircuitComponent.Type.GROUND:
			hbox_val.visible = true
			if not edit_val.has_focus():
				edit_val.text = comp.value
		else:
			hbox_val.visible = false

		btn_rotate.visible = true
		btn_delete.visible = true
	else:
		# Check if wire
		var wire_found = false
		for w in state.wires:
			if w.id == current_selected_id:
				wire_found = true
				lbl_empty.visible = false
				lbl_title.visible = true
				lbl_title.text = "Wire Connection"
				lbl_id.visible = true
				lbl_id.text = "ID: " + w.id
				lbl_pos.visible = true
				lbl_pos.text = "%s ➔ %s" % [w.from_pin_id, w.to_pin_id]
				hbox_val.visible = false
				btn_rotate.visible = false
				btn_delete.visible = true
				break
		if not wire_found:
			_show_empty()

func _show_empty() -> void:
	lbl_empty.visible = true
	lbl_title.visible = false
	lbl_id.visible = false
	lbl_pos.visible = false
	hbox_val.visible = false
	btn_rotate.visible = false
	btn_delete.visible = false

func _get_comp_type_name(t: CircuitComponent.Type) -> String:
	match t:
		CircuitComponent.Type.RESISTOR: return "Resistor"
		CircuitComponent.Type.VOLTAGE_SOURCE: return "DC Voltage Source"
		CircuitComponent.Type.CURRENT_SOURCE: return "DC Current Source"
		CircuitComponent.Type.GROUND: return "Ground Reference (0)"
		CircuitComponent.Type.NET_LABEL: return "Net Label"
	return "Component"

func _on_value_submitted(new_text: String) -> void:
	if current_selected_id != "":
		intent_dispatched.emit(CircuitIntent.create_update_component_value(current_selected_id, new_text))

func _on_value_focus_exited() -> void:
	if current_selected_id != "":
		intent_dispatched.emit(CircuitIntent.create_update_component_value(current_selected_id, edit_val.text))

func _on_rotate_pressed() -> void:
	intent_dispatched.emit(CircuitIntent.create_rotate_component(current_selected_id))

func _on_delete_pressed() -> void:
	intent_dispatched.emit(CircuitIntent.create_delete_selected())
