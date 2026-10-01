class_name WorkbenchPanel
extends PanelContainer

## WorkbenchPanel: Bottom docking panel with 3 tabs:
## 1. Netlist + Coordinates (Always-editable Reconstructor & AI Vision)
## 2. SPICE Simulation (.op) and Netlist viewer (showing V, I, P)
## 3. Interactive SPICE Terminal (direct ngspice command execution)

signal intent_dispatched(intent: CircuitIntent)

var tabs: TabContainer

# Tab 1: Reconstructor / Netlist + Coords
var txt_reconstruct_input: TextEdit
var lbl_reconstruct_status: Label
var lbl_image_info: Label
var input_model: LineEdit
var current_image_path: String = ""

# Tab 2: Simulation .op & Netlist
var txt_generated_netlist: TextEdit
var txt_sim_report: TextEdit
var lbl_sim_status: Label
var warnings_container: VBoxContainer
var btn_simulate: Button

# Tab 3: Terminal
var txt_terminal: TextEdit
var input_terminal_cmd: LineEdit
var last_terminal_len: int = 0

func _init() -> void:
	custom_minimum_size = Vector2(0, 240)

func _ready() -> void:
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(tabs)

	# Build tabs
	_build_reconstructor_tab()
	_build_simulation_tab()
	_build_terminal_tab()

# ==========================================
# TAB 1: RECONSTRUCTOR (NETLIST + COORDS)
# ==========================================
func _build_reconstructor_tab() -> void:
	var tab_vbox = VBoxContainer.new()
	tab_vbox.name = "⚡ Netlist + Coordenadas"
	tab_vbox.add_theme_constant_override("separation", 6)
	tabs.add_child(tab_vbox)

	# Header controls
	var hbox_header = HBoxContainer.new()
	hbox_header.add_theme_constant_override("separation", 8)
	tab_vbox.add_child(hbox_header)

	var title = Label.new()
	title.text = "⚡ Editor Topológico"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	hbox_header.add_child(title)

	lbl_reconstruct_status = Label.new()
	lbl_reconstruct_status.text = "• Inserta o edita netlist con coordenadas para reconstruir en el canvas."
	lbl_reconstruct_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_reconstruct_status.add_theme_font_size_override("font_size", 11)
	lbl_reconstruct_status.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	hbox_header.add_child(lbl_reconstruct_status)

	lbl_image_info = Label.new()
	lbl_image_info.text = "Img: Ninguna"
	lbl_image_info.add_theme_font_size_override("font_size", 11)
	lbl_image_info.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	hbox_header.add_child(lbl_image_info)

	var btn_re_analyze = Button.new()
	btn_re_analyze.text = "🔄 Re-analizar con IA"
	btn_re_analyze.tooltip_text = "Vuelve a enviar la imagen a Gemini para extraer netlist y posiciones"
	btn_re_analyze.add_theme_font_size_override("font_size", 11)
	btn_re_analyze.pressed.connect(_on_re_analyze_pressed)
	hbox_header.add_child(btn_re_analyze)

	# Main Textarea (ALWAYS available and editable!)
	txt_reconstruct_input = TextEdit.new()
	txt_reconstruct_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	txt_reconstruct_input.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	txt_reconstruct_input.add_theme_font_size_override("font_size", 12)
	txt_reconstruct_input.placeholder_text = "* Formato: Netlist SPICE con posiciones de nodos\n* positions\nN0 0,4 ; N1 0,2 ; N2 2,2 ; N3 4,2\nV1 1 0 DC 12V\nR1 1 2 10k\nR2 2 0 4.7k\n.end"
	tab_vbox.add_child(txt_reconstruct_input)

	# Action Buttons
	var hbox_actions = HBoxContainer.new()
	hbox_actions.alignment = BoxContainer.ALIGNMENT_END
	hbox_actions.add_theme_constant_override("separation", 8)
	tab_vbox.add_child(hbox_actions)

	var btn_load_example = Button.new()
	btn_load_example.text = "📝 Cargar Ejemplo"
	btn_load_example.tooltip_text = "Cargar ejemplo de circuito con coordenadas en este editor"
	btn_load_example.pressed.connect(_on_load_example_pressed)
	hbox_actions.add_child(btn_load_example)

	var btn_clear = Button.new()
	btn_clear.text = "🧹 Limpiar"
	btn_clear.pressed.connect(func(): txt_reconstruct_input.text = "")
	hbox_actions.add_child(btn_clear)

	var btn_copy = Button.new()
	btn_copy.text = "📋 Copiar"
	btn_copy.pressed.connect(func(): DisplayServer.clipboard_set(txt_reconstruct_input.text))
	hbox_actions.add_child(btn_copy)

	var btn_build = Button.new()
	btn_build.text = "⚡ Reconstruir Circuito en Canvas"
	btn_build.tooltip_text = "Genera el esquemático en el canvas a partir del texto actual"
	btn_build.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	btn_build.pressed.connect(func(): intent_dispatched.emit(CircuitIntent.create_build_circuit_from_ai(txt_reconstruct_input.text)))
	hbox_actions.add_child(btn_build)

# ==========================================
# TAB 2: SIMULATION .OP & NETLIST
# ==========================================
func _build_simulation_tab() -> void:
	var tab_vbox = VBoxContainer.new()
	tab_vbox.name = "📜 Simulación SPICE (.op)"
	tab_vbox.add_theme_constant_override("separation", 6)
	tabs.add_child(tab_vbox)

	# Top status and simulate button
	var hbox_header = HBoxContainer.new()
	hbox_header.add_theme_constant_override("separation", 8)
	tab_vbox.add_child(hbox_header)

	lbl_sim_status = Label.new()
	lbl_sim_status.text = "• Listo para simular."
	lbl_sim_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_sim_status.add_theme_font_size_override("font_size", 12)
	hbox_header.add_child(lbl_sim_status)

	var btn_copy_netlist = Button.new()
	btn_copy_netlist.text = "📋 Copiar Netlist"
	btn_copy_netlist.pressed.connect(func(): DisplayServer.clipboard_set(txt_generated_netlist.text))
	hbox_header.add_child(btn_copy_netlist)

	btn_simulate = Button.new()
	btn_simulate.text = "▶ Ejecutar Simulación (.op)"
	btn_simulate.tooltip_text = "Calcula V y P en componentes y corrientes I en ramas usando ngspice"
	btn_simulate.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	btn_simulate.pressed.connect(func(): intent_dispatched.emit(CircuitIntent.create_run_simulation()))
	hbox_header.add_child(btn_simulate)

	# Split view: Netlist on left, Results on right
	var h_split = HSplitContainer.new()
	h_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h_split.split_offset = 420
	tab_vbox.add_child(h_split)

	# Left side: Generated Netlist
	var vbox_left = VBoxContainer.new()
	vbox_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_split.add_child(vbox_left)

	var lbl_netlist_title = Label.new()
	lbl_netlist_title.text = "Netlist Generado (Canvas):"
	lbl_netlist_title.add_theme_font_size_override("font_size", 11)
	lbl_netlist_title.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox_left.add_child(lbl_netlist_title)

	txt_generated_netlist = TextEdit.new()
	txt_generated_netlist.editable = false
	txt_generated_netlist.size_flags_vertical = Control.SIZE_EXPAND_FILL
	txt_generated_netlist.add_theme_font_size_override("font_size", 12)
	vbox_left.add_child(txt_generated_netlist)

	warnings_container = VBoxContainer.new()
	vbox_left.add_child(warnings_container)

	# Right side: Simulation Results
	var vbox_right = VBoxContainer.new()
	vbox_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_split.add_child(vbox_right)

	var lbl_results_title = Label.new()
	lbl_results_title.text = "Resultados Punto de Operación (.op):"
	lbl_results_title.add_theme_font_size_override("font_size", 11)
	lbl_results_title.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))
	vbox_right.add_child(lbl_results_title)

	txt_sim_report = TextEdit.new()
	txt_sim_report.editable = false
	txt_sim_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	txt_sim_report.add_theme_font_size_override("font_size", 12)
	txt_sim_report.text = "Presiona '▶ Ejecutar Simulación (.op)' para simular el circuito actual.\nSe mostrarán voltajes por nodo, caídas de tensión (ΔV), corrientes (I) y potencias disipadas (P)."
	vbox_right.add_child(txt_sim_report)

# ==========================================
# TAB 3: SPICE TERMINAL
# ==========================================
func _build_terminal_tab() -> void:
	var tab_vbox = VBoxContainer.new()
	tab_vbox.name = "💻 Terminal SPICE"
	tab_vbox.add_theme_constant_override("separation", 6)
	tabs.add_child(tab_vbox)

	# Quick command bar
	var hbox_quick = HBoxContainer.new()
	hbox_quick.add_theme_constant_override("separation", 6)
	tab_vbox.add_child(hbox_quick)

	var lbl_quick = Label.new()
	lbl_quick.text = "Comandos Rápidos:"
	lbl_quick.add_theme_font_size_override("font_size", 11)
	lbl_quick.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	hbox_quick.add_child(lbl_quick)

	var btn_q_op = Button.new()
	btn_q_op.text = "op"
	btn_q_op.add_theme_font_size_override("font_size", 11)
	btn_q_op.pressed.connect(func(): intent_dispatched.emit(CircuitIntent.create_execute_spice_command("op")))
	hbox_quick.add_child(btn_q_op)

	var btn_q_print = Button.new()
	btn_q_print.text = "print all"
	btn_q_print.add_theme_font_size_override("font_size", 11)
	btn_q_print.pressed.connect(func(): intent_dispatched.emit(CircuitIntent.create_execute_spice_command("print all")))
	hbox_quick.add_child(btn_q_print)

	var btn_q_display = Button.new()
	btn_q_display.text = "display"
	btn_q_display.add_theme_font_size_override("font_size", 11)
	btn_q_display.pressed.connect(func(): intent_dispatched.emit(CircuitIntent.create_execute_spice_command("display")))
	hbox_quick.add_child(btn_q_display)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_quick.add_child(spacer)

	var btn_clear_term = Button.new()
	btn_clear_term.text = "🧹 Limpiar Terminal"
	btn_clear_term.add_theme_font_size_override("font_size", 11)
	btn_clear_term.pressed.connect(func(): txt_terminal.text = "")
	hbox_quick.add_child(btn_clear_term)

	# Terminal Output Console
	txt_terminal = TextEdit.new()
	txt_terminal.editable = false
	txt_terminal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	txt_terminal.add_theme_font_size_override("font_size", 12)
	txt_terminal.text = "ngspice interactive console ready.\nType commands (e.g. 'op', 'print all', 'display') and press Enter.\n"
	tab_vbox.add_child(txt_terminal)

	# Command Input Line
	var hbox_cmd = HBoxContainer.new()
	hbox_cmd.add_theme_constant_override("separation", 6)
	tab_vbox.add_child(hbox_cmd)

	var prompt_lbl = Label.new()
	prompt_lbl.text = "ngspice >"
	prompt_lbl.add_theme_color_override("font_color", Color(0.2, 0.9, 0.5))
	prompt_lbl.add_theme_font_size_override("font_size", 12)
	hbox_cmd.add_child(prompt_lbl)

	input_terminal_cmd = LineEdit.new()
	input_terminal_cmd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_terminal_cmd.placeholder_text = "Escribe comando SPICE (ej: op, print all, display, show R1) y presiona Enter..."
	input_terminal_cmd.text_submitted.connect(_on_terminal_cmd_submitted)
	hbox_cmd.add_child(input_terminal_cmd)

	var btn_send = Button.new()
	btn_send.text = "Enviar"
	btn_send.pressed.connect(func(): _on_terminal_cmd_submitted(input_terminal_cmd.text))
	hbox_cmd.add_child(btn_send)

# ==========================================
# STATE UPDATE (MVI)
# ==========================================
func update_state(state: CircuitState) -> void:
	if not state:
		return

	# Update Tab 1 (Reconstructor & AI Vision)
	current_image_path = state.ai_image_path
	if state.ai_image_path != "":
		lbl_image_info.text = "Img: " + state.ai_image_path.get_file()
		lbl_image_info.tooltip_text = state.ai_image_path
	else:
		lbl_image_info.text = "Img: Ninguna"

	if state.ai_is_loading:
		lbl_reconstruct_status.text = "⏳ Extrayendo circuito con IA..."
		lbl_reconstruct_status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	elif state.ai_error != "":
		lbl_reconstruct_status.text = "❌ Error IA: " + state.ai_error
		lbl_reconstruct_status.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		lbl_reconstruct_status.text = "• Listo para ingresar o editar netlist."
		lbl_reconstruct_status.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
		if state.ai_response_text != "" and txt_reconstruct_input.text.is_empty():
			txt_reconstruct_input.text = state.ai_response_text
		elif state.ai_response_text != "" and state.ai_panel_visible:
			txt_reconstruct_input.text = state.ai_response_text

	# Update Tab 2 (Generated Netlist & Simulation .op)
	txt_generated_netlist.text = state.netlist_text

	if state.has_ground:
		lbl_sim_status.text = "✓ Tierra (0) detectada. Listo para simular."
		lbl_sim_status.add_theme_color_override("font_color", Color(0.2, 0.85, 0.4))
	else:
		lbl_sim_status.text = "⚠ Falta Tierra (0). Añade un componente Ground."
		lbl_sim_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))

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

	if not state.sim_report.is_empty():
		txt_sim_report.text = state.sim_report

	# Update Tab 3 (Terminal log)
	if state.terminal_log != txt_terminal.text:
		txt_terminal.text = state.terminal_log
		txt_terminal.set_caret_line(txt_terminal.get_line_count())

func _on_terminal_cmd_submitted(cmd_text: String) -> void:
	var cmd = cmd_text.strip_edges()
	if cmd.is_empty():
		return
	input_terminal_cmd.clear()
	intent_dispatched.emit(CircuitIntent.create_execute_spice_command(cmd))

func _on_re_analyze_pressed() -> void:
	if current_image_path != "":
		intent_dispatched.emit(CircuitIntent.create_analyze_image(current_image_path))

func _on_load_example_pressed() -> void:
	txt_reconstruct_input.text = """* positions
N0 0,4 ; N1 0,2 ; N2 2,2 ; N3 4,2 ; N4 2,4
* Fuente de voltaje de 10 V
V1 1 0 DC 10V
* Fuente de corriente de 10 A
I1 1 3 DC 10A
* Resistores
R1 1 3 5
R2 1 2 2
V2 2 3 DC 6V
R3 2 4 2
I2 4 2 DC 6
R4 3 4 4
.end"""
