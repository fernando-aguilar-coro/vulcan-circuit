class_name AIAssistantPanel
extends PanelContainer

signal intent_dispatched(intent: CircuitIntent)



var lbl_status: Label
var lbl_image_path: Label
var input_model: LineEdit
var text_response: TextEdit
var btn_close: Button
var btn_copy: Button
var progress_indicator: ProgressBar
var current_image_path: String = ""

func _init() -> void:
	custom_minimum_size = Vector2(450, 320)
	visible = false

func _ready() -> void:
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title Header
	var hbox_header = HBoxContainer.new()
	vbox.add_child(hbox_header)

	var title = Label.new()
	title.text = "🤖 Gemini Circuit Vision"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_header.add_child(title)

	btn_close = Button.new()
	btn_close.text = "✕"
	btn_close.pressed.connect(func(): intent_dispatched.emit(CircuitIntent.create_toggle_ai_panel(false)))
	hbox_header.add_child(btn_close)

	# Model Input Row
	var hbox_model = HBoxContainer.new()
	hbox_model.add_theme_constant_override("separation", 6)
	vbox.add_child(hbox_model)

	var lbl_model = Label.new()
	lbl_model.text = "Model:"
	lbl_model.add_theme_font_size_override("font_size", 11)
	lbl_model.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	hbox_model.add_child(lbl_model)

	input_model = LineEdit.new()
	input_model.text = AIConfig.get_model()
	input_model.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_model.add_theme_font_size_override("font_size", 11)
	input_model.tooltip_text = "Gemini model name (e.g. gemini-3.5-flash-lite, gemini-flash-lite-latest, gemini-3.1-flash-lite, gemini-3.8-flash)"
	input_model.text_changed.connect(func(new_text: String): AIConfig.set_model(new_text))
	hbox_model.add_child(input_model)

	var opt_model_preset = OptionButton.new()
	opt_model_preset.add_item("gemini-3.5-flash-lite")
	opt_model_preset.add_item("gemini-flash-lite-latest")
	opt_model_preset.add_item("gemini-3.1-flash-lite")
	opt_model_preset.add_item("gemini-3.5-flash")
	opt_model_preset.add_item("gemini-3.8-flash")
	opt_model_preset.add_item("gemini-2.5-pro")
	opt_model_preset.add_theme_font_size_override("font_size", 11)
	opt_model_preset.item_selected.connect(func(idx: int):
		var selected_name = opt_model_preset.get_item_text(idx)
		input_model.text = selected_name
		AIConfig.set_model(selected_name)
	)
	hbox_model.add_child(opt_model_preset)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Image Info & Quick Re-run button
	var hbox_img_bar = HBoxContainer.new()
	vbox.add_child(hbox_img_bar)

	lbl_image_path = Label.new()
	lbl_image_path.text = "Image: None"
	lbl_image_path.add_theme_font_size_override("font_size", 11)
	lbl_image_path.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	lbl_image_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_image_path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox_img_bar.add_child(lbl_image_path)

	var btn_re_analyze = Button.new()
	btn_re_analyze.text = "🔄 Re-analizar Imagen"
	btn_re_analyze.tooltip_text = "Re-generar con Gemini usando el netlist topológico y coordenadas"
	btn_re_analyze.add_theme_font_size_override("font_size", 11)
	btn_re_analyze.pressed.connect(_on_re_analyze_pressed)
	hbox_img_bar.add_child(btn_re_analyze)

	lbl_status = Label.new()
	lbl_status.text = "Ready"
	lbl_status.add_theme_font_size_override("font_size", 12)
	vbox.add_child(lbl_status)

	# Text area for AI Response
	text_response = TextEdit.new()
	text_response.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_response.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_response.add_theme_font_size_override("font_size", 12)
	vbox.add_child(text_response)

	# Bottom Action Buttons
	var hbox_actions = HBoxContainer.new()
	hbox_actions.alignment = BoxContainer.ALIGNMENT_END
	hbox_actions.add_theme_constant_override("separation", 8)
	vbox.add_child(hbox_actions)

	# Single primary button: Reconstruct Circuit on Canvas
	var btn_create = Button.new()
	btn_create.text = "⚡ Reconstruir Circuito en Canvas"
	btn_create.tooltip_text = "Generar esquemático en el canvas a partir del netlist topológico y coordenadas"
	btn_create.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	btn_create.pressed.connect(func(): intent_dispatched.emit(CircuitIntent.create_build_circuit_from_ai(text_response.text)))
	hbox_actions.add_child(btn_create)

	btn_copy = Button.new()
	btn_copy.text = "📋 Copy"
	btn_copy.pressed.connect(_on_copy_pressed)
	hbox_actions.add_child(btn_copy)

func update_ai_state(state: CircuitState) -> void:
	visible = state.ai_panel_visible
	if not visible:
		return

	current_image_path = state.ai_image_path
	if state.ai_image_path != "":
		lbl_image_path.text = "Source: " + state.ai_image_path.get_file()
		lbl_image_path.tooltip_text = state.ai_image_path
	else:
		lbl_image_path.text = "Image: None"

	if state.ai_is_loading:
		lbl_status.text = "⏳ Extracting circuit with " + AIConfig.get_model() + "..."
		lbl_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		if text_response.text == "":
			text_response.text = "Sending request to Google Gemini API...\nModel: " + AIConfig.get_model() + "\nPlease wait..."
	elif state.ai_error != "":
		lbl_status.text = "❌ Error: " + state.ai_error
		lbl_status.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		text_response.text = "Error details:\n" + state.ai_error
	else:
		lbl_status.text = "✓ Circuit extracted successfully!"
		lbl_status.add_theme_color_override("font_color", Color(0.2, 0.85, 0.4))
		if state.ai_response_text != "":
			text_response.text = state.ai_response_text

func _on_re_analyze_pressed() -> void:
	if current_image_path != "":
		intent_dispatched.emit(CircuitIntent.create_analyze_image(current_image_path))

func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(text_response.text)
	btn_copy.text = "✓ Copied!"
	var t = get_tree().create_timer(1.5)
	t.timeout.connect(func(): if is_instance_valid(btn_copy): btn_copy.text = "📋 Copy")
