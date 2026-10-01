class_name CircuitComponent
extends RefCounted


enum Type {
	RESISTOR,
	VOLTAGE_SOURCE,
	CURRENT_SOURCE,
	GROUND,
	CAPACITOR,
	INDUCTOR,
	DIODE,
	BJT_NPN,
	BJT_PNP,
	OPAMP,
	POTENTIOMETER,
	TRANSFORMER,
	SCR,
	TRIAC,
	IC,
	NET_LABEL,
	JUNCTION
}

var id: String = ""
var type: Type = Type.RESISTOR
var position: Vector2 = Vector2.ZERO
var rotation_deg: int = 0
var value: String = "1k"
var display_label: String = ""
var is_virtual: bool = false
var pins: Array[CircuitPin] = []
var ic_data: Dictionary = {}
var ic_box_size: Vector2 = Vector2(70, 60)

func _init(p_id: String = "", p_type: Type = Type.RESISTOR, p_pos: Vector2 = Vector2.ZERO, p_val: String = "") -> void:
	id = p_id
	type = p_type
	position = p_pos
	rotation_deg = 0
	display_label = id
	_setup_default_values_and_pins(p_val)

func _setup_default_values_and_pins(p_val: String) -> void:
	pins.clear()
	match type:
		Type.RESISTOR:
			value = p_val if p_val != "" else "1k"
			# Resistor terminal pins: horizontal (-40, 0) and (+40, 0)
			var p1 = CircuitPin.new(id, "p1", Vector2(-40, 0), false)
			var p2 = CircuitPin.new(id, "p2", Vector2(40, 0), false)
			pins.append(p1)
			pins.append(p2)
		Type.VOLTAGE_SOURCE:
			value = p_val if p_val != "" else "5"
			# Pos pin at top (0, -40), neg pin at bottom (0, 40)
			var pos_pin = CircuitPin.new(id, "pos", Vector2(0, -40), false)
			var neg_pin = CircuitPin.new(id, "neg", Vector2(0, 40), false)
			pins.append(pos_pin)
			pins.append(neg_pin)
		Type.CURRENT_SOURCE:
			value = p_val if p_val != "" else "1m"
			# Pos pin (outflow) at top (0, -40), neg pin (inflow) at bottom (0, 40)
			var pos_pin = CircuitPin.new(id, "pos", Vector2(0, -40), false)
			var neg_pin = CircuitPin.new(id, "neg", Vector2(0, 40), false)
			pins.append(pos_pin)
			pins.append(neg_pin)
		Type.GROUND:
			value = "0"
			# Ground terminal pin at top (0, -20)
			var gnd_pin = CircuitPin.new(id, "gnd", Vector2(0, -20), true)
			pins.append(gnd_pin)
		Type.CAPACITOR:
			value = p_val if p_val != "" else "1uF"
			pins.append(CircuitPin.new(id, "p1", Vector2(-35, 0), false))
			pins.append(CircuitPin.new(id, "p2", Vector2(35, 0), false))
		Type.INDUCTOR:
			value = p_val if p_val != "" else "10mH"
			pins.append(CircuitPin.new(id, "p1", Vector2(-35, 0), false))
			pins.append(CircuitPin.new(id, "p2", Vector2(35, 0), false))
		Type.DIODE:
			value = p_val if p_val != "" else "1N4148"
			pins.append(CircuitPin.new(id, "anode", Vector2(-35, 0), false))
			pins.append(CircuitPin.new(id, "cathode", Vector2(35, 0), false))
		Type.BJT_NPN:
			value = p_val if p_val != "" else "2N2222"
			pins.append(CircuitPin.new(id, "B", Vector2(-35, 0), false))
			pins.append(CircuitPin.new(id, "C", Vector2(20, -35), false))
			pins.append(CircuitPin.new(id, "E", Vector2(20, 35), false))
		Type.BJT_PNP:
			value = p_val if p_val != "" else "2N2907"
			pins.append(CircuitPin.new(id, "B", Vector2(-35, 0), false))
			pins.append(CircuitPin.new(id, "E", Vector2(20, -35), false))
			pins.append(CircuitPin.new(id, "C", Vector2(20, 35), false))
		Type.OPAMP:
			value = p_val if p_val != "" else "LM741"
			pins.append(CircuitPin.new(id, "in_neg", Vector2(-40, -18), false))
			pins.append(CircuitPin.new(id, "in_pos", Vector2(-40, 18), false))
			pins.append(CircuitPin.new(id, "out", Vector2(40, 0), false))
		Type.POTENTIOMETER:
			value = p_val if p_val != "" else "10k"
			pins.append(CircuitPin.new(id, "t1", Vector2(-40, 0), false))
			pins.append(CircuitPin.new(id, "t2", Vector2(40, 0), false))
			pins.append(CircuitPin.new(id, "wiper", Vector2(0, 40), false))
		Type.TRANSFORMER:
			value = p_val if p_val != "" else "1:1"
			pins.append(CircuitPin.new(id, "pri_pos", Vector2(-40, -20), false))
			pins.append(CircuitPin.new(id, "pri_neg", Vector2(-40, 20), false))
			pins.append(CircuitPin.new(id, "sec_pos", Vector2(40, -20), false))
			pins.append(CircuitPin.new(id, "sec_neg", Vector2(40, 20), false))
		Type.SCR:
			value = p_val if p_val != "" else "2N5064"
			pins.append(CircuitPin.new(id, "anode", Vector2(0, -40), false))
			pins.append(CircuitPin.new(id, "cathode", Vector2(0, 40), false))
			pins.append(CircuitPin.new(id, "gate", Vector2(-40, 20), false))
		Type.TRIAC:
			value = p_val if p_val != "" else "BT136"
			pins.append(CircuitPin.new(id, "mt2", Vector2(0, -40), false))
			pins.append(CircuitPin.new(id, "mt1", Vector2(0, 40), false))
			pins.append(CircuitPin.new(id, "gate", Vector2(-40, 20), false))
		Type.IC:
			value = p_val if p_val != "" else "IC"
			ic_data["model"] = value
			display_label = value
		Type.NET_LABEL:
			value = p_val if p_val != "" else "VCC"
			# Single terminal pin at origin (0, 0)
			pins.append(CircuitPin.new(id, "pin", Vector2.ZERO, false))
		Type.JUNCTION:
			value = "dot"
			pins.append(CircuitPin.new(id, "dot", Vector2.ZERO, false))

func setup_ic_pins(p_model: String, pin_names: Array) -> void:
	pins.clear()
	ic_data["model"] = p_model
	value = p_model if p_model != "" else "IC"
	display_label = p_model if p_model != "" else id

	var u_mod = p_model.to_upper()
	# Check for 3-pin standard voltage regulators (e.g. 7805, 317, 1117)
	if pin_names.size() == 3 and (u_mod.contains("78") or u_mod.contains("79") or u_mod.contains("317") or u_mod.contains("1117") or u_mod.contains("REG")):
		ic_box_size = Vector2(70, 50)
		pins.append(CircuitPin.new(id, str(pin_names[0]), Vector2(-45, 0), false)) # IN
		pins.append(CircuitPin.new(id, str(pin_names[1]), Vector2(0, 35), false))  # GND / ADJ
		pins.append(CircuitPin.new(id, str(pin_names[2]), Vector2(45, 0), false))  # OUT
		return

	# General dual-in-line pin distribution (Left vs Right)
	var total_pins = pin_names.size()
	if total_pins == 0:
		ic_box_size = Vector2(70, 50)
		return

	var left_count = int(ceil(float(total_pins) / 2.0))
	var right_count = total_pins - left_count
	var rows = max(left_count, right_count, 2)
	var step_y = 20.0
	var box_height = max(50.0, rows * step_y + 20.0)
	var box_width = 70.0
	ic_box_size = Vector2(box_width, box_height)

	# Left side pins (top to bottom)
	for i in range(left_count):
		var y_off = -((left_count - 1) * step_y) / 2.0 + i * step_y
		pins.append(CircuitPin.new(id, str(pin_names[i]), Vector2(-box_width / 2.0 - 10.0, y_off), false))

	# Right side pins (bottom to top, or top to bottom)
	for j in range(right_count):
		var y_off = -((right_count - 1) * step_y) / 2.0 + j * step_y
		pins.append(CircuitPin.new(id, str(pin_names[left_count + j]), Vector2(box_width / 2.0 + 10.0, y_off), false))

func get_pin(pin_name: String) -> CircuitPin:
	for pin in pins:
		if pin.name == pin_name:
			return pin
	return null

func get_pin_by_id(pin_id: String) -> CircuitPin:
	for pin in pins:
		if pin.id == pin_id:
			return pin
	return null

func get_pin_world_position(pin_name: String) -> Vector2:
	var pin = get_pin(pin_name)
	if pin:
		return pin.get_world_position(position, rotation_deg)
	return position

func get_spice_prefix() -> String:
	match type:
		Type.RESISTOR: return "R"
		Type.CAPACITOR: return "C"
		Type.INDUCTOR: return "L"
		Type.DIODE: return "D"
		Type.VOLTAGE_SOURCE: return "V"
		Type.CURRENT_SOURCE: return "I"
		Type.BJT_NPN, Type.BJT_PNP: return "Q"
		Type.OPAMP: return "X"
		Type.POTENTIOMETER: return "XPOT"
		Type.TRANSFORMER: return "XTR"
		Type.SCR: return "XSCR"
		Type.TRIAC: return "XTRIAC"
		Type.IC: return "X"
		Type.GROUND: return "GND"
		Type.NET_LABEL: return "LBL"
		Type.JUNCTION: return "J"
	return "X"

func clone() -> RefCounted:
	var c = get_script().new(id, type, position, value)
	c.rotation_deg = rotation_deg
	c.display_label = display_label
	c.is_virtual = is_virtual
	c.ic_data = ic_data.duplicate(true)
	c.ic_box_size = ic_box_size
	if type == Type.IC:
		c.pins.clear()
		for p in pins:
			c.pins.append(p.duplicate_pin(c.id))
	return c
