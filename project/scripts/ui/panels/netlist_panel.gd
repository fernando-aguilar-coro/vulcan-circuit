class_name NetlistPanel
extends PanelContainer



var text_edit: TextEdit
var lbl_status: Label
var btn_copy: Button
var btn_toggle: Button
var warnings_container: VBoxContainer
var is_collapsed: bool = false
var panel_content: VBoxContainer

func _init() -> void:
	custom_minimum_size = Vector2(0, 180)

func _ready() -> void:
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(main_vbox)

	# Header Bar
	var header_hbox = HBoxContainer.new()
	main_vbox.add_child(header_hbox)

	var title = Label.new()
	title.text = "📜 ngspice Netlist"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	header_hbox.add_child(title)

	lbl_status = Label.new()
	lbl_status.text = "• Ready"
	lbl_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_status.add_theme_font_size_override("font_size", 12)
	header_hbox.add_child(lbl_status)

	btn_copy = Button.new()
	btn_copy.text = "📋 Copy Netlist"
	btn_copy.pressed.connect(_on_copy_pressed)
	header_hbox.add_child(btn_copy)

	btn_toggle = Button.new()
	btn_toggle.text = "▼"
	btn_toggle.pressed.connect(_on_toggle_pressed)
	header_hbox.add_child(btn_toggle)

	# Collapsible Content
	panel_content = VBoxContainer.new()
	panel_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_content.add_theme_constant_override("separation", 6)
	main_vbox.add_child(panel_content)

	text_edit = TextEdit.new()
	text_edit.editable = false
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_edit.add_theme_font_size_override("font_size", 12)
	panel_content.add_child(text_edit)

	warnings_container = VBoxContainer.new()
	panel_content.add_child(warnings_container)

func update_netlist(state: CircuitState) -> void:
	if not state:
		return

	text_edit.text = state.netlist_text

	if state.has_ground:
		lbl_status.text = "✓ Ground (0) detected. Ready for simulation."
		lbl_status.add_theme_color_override("font_color", Color(0.2, 0.85, 0.4))
	else:
		lbl_status.text = "⚠ Missing Ground (0). Add a Ground element."
		lbl_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))

	# Clear previous warnings
	for child in warnings_container.get_children():
		child.queue_free()

	for err in state.errors:
		var err_lbl = Label.new()
		err_lbl.text = "🛑 " + err
		err_lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		err_lbl.add_theme_font_size_override("font_size", 11)
		warnings_container.add_child(err_lbl)

	for warn in state.warnings:
		var warn_lbl = Label.new()
		warn_lbl.text = "⚠ " + warn
		warn_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		warn_lbl.add_theme_font_size_override("font_size", 11)
		warnings_container.add_child(warn_lbl)

func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(text_edit.text)
	btn_copy.text = "✓ Copied!"
	var timer = get_tree().create_timer(1.5)
	timer.timeout.connect(func(): if is_instance_valid(btn_copy): btn_copy.text = "📋 Copy Netlist")

func _on_toggle_pressed() -> void:
	is_collapsed = not is_collapsed
	panel_content.visible = not is_collapsed
	btn_toggle.text = "▲" if is_collapsed else "▼"
	custom_minimum_size.y = 40 if is_collapsed else 180
