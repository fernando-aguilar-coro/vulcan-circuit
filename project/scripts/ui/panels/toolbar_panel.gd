class_name ToolbarPanel
extends PanelContainer

signal intent_dispatched(intent: CircuitIntent)



var btn_select: Button
var btn_wire: Button
var btn_resistor: Button
var btn_voltage: Button
var btn_current: Button
var btn_ground: Button
var btn_delete: Button
var btn_clear: Button
var btn_sample: Button

var tool_buttons: Dictionary = {}

func _init() -> void:
	custom_minimum_size = Vector2(0, 46)

func _ready() -> void:
	var h_box = HBoxContainer.new()
	h_box.add_theme_constant_override("separation", 8)
	add_child(h_box)

	# Title / Brand
	var title = Label.new()
	title.text = "⚡ ProtoAI Circuit"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	h_box.add_child(title)

	var sep1 = VSeparator.new()
	h_box.add_child(sep1)

	# Tool buttons
	btn_select = _create_tool_button("👆 Select [S]", CircuitState.Tool.SELECT)
	btn_wire = _create_tool_button("⚡ Wire [W]", CircuitState.Tool.WIRE)
	btn_resistor = _create_tool_button("〰️ Resistor [R]", CircuitState.Tool.ADD_RESISTOR)
	btn_voltage = _create_tool_button("🔋 DC Volt [V]", CircuitState.Tool.ADD_VOLTAGE_SOURCE)
	btn_current = _create_tool_button("🔃 DC Curr [I]", CircuitState.Tool.ADD_CURRENT_SOURCE)
	btn_ground = _create_tool_button("⏚ Ground [G]", CircuitState.Tool.ADD_GROUND)
	btn_delete = _create_tool_button("🗑️ Delete [Del]", CircuitState.Tool.DELETE)

	h_box.add_child(btn_select)
	h_box.add_child(btn_wire)
	h_box.add_child(btn_resistor)
	h_box.add_child(btn_voltage)
	h_box.add_child(btn_current)
	h_box.add_child(btn_ground)
	h_box.add_child(btn_delete)

	var sep2 = VSeparator.new()
	h_box.add_child(sep2)

	# Sample & Clear
	btn_sample = Button.new()
	btn_sample.text = "📋 Load Sample"
	btn_sample.tooltip_text = "Load Voltage Divider circuit preset"
	btn_sample.pressed.connect(func(): intent_dispatched.emit(CircuitIntent.create_load_preset("VoltageDivider")))
	h_box.add_child(btn_sample)

	btn_clear = Button.new()
	btn_clear.text = "🧹 Clear"
	btn_clear.pressed.connect(func(): intent_dispatched.emit(CircuitIntent.create_clear_circuit()))
	h_box.add_child(btn_clear)

	var sep3 = VSeparator.new()
	h_box.add_child(sep3)

	# AI Vision Button
	var btn_ai_image = Button.new()
	btn_ai_image.text = "📷 Importar Imagen (IA)"
	btn_ai_image.tooltip_text = "Convertir imagen esquemática a circuito con IA (Netlist + Dirección + Coordenadas)"
	btn_ai_image.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	btn_ai_image.pressed.connect(_on_ai_image_pressed)
	h_box.add_child(btn_ai_image)

	# FileDialog for Image Selection
	var file_dialog = FileDialog.new()
	file_dialog.name = "AIFileDialog"
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png ; PNG Images", "*.jpg, *.jpeg ; JPEG Images", "*.webp ; WebP Images"])
	file_dialog.title = "Seleccionar Imagen de Circuito para IA"
	file_dialog.file_selected.connect(func(path: String): intent_dispatched.emit(CircuitIntent.create_analyze_image(path)))
	add_child(file_dialog)

func _on_ai_image_pressed() -> void:
	var dlg = get_node_or_null("AIFileDialog") as FileDialog
	if dlg:
		dlg.popup_file_dialog()

func _create_tool_button(label: String, tool: CircuitState.Tool) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.pressed.connect(func(): intent_dispatched.emit(CircuitIntent.create_select_tool(tool)))
	tool_buttons[tool] = btn
	return btn

func update_active_tool(tool: CircuitState.Tool) -> void:
	for t in tool_buttons:
		tool_buttons[t].button_pressed = (t == tool)
