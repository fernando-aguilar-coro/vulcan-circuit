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
		Type.NET_LABEL:
			value = p_val if p_val != "" else "VCC"
			# Single terminal pin at origin (0, 0)
			pins.append(CircuitPin.new(id, "pin", Vector2.ZERO, false))
		Type.JUNCTION:
			value = "dot"
			pins.append(CircuitPin.new(id, "dot", Vector2.ZERO, false))

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
		Type.GROUND: return "GND"
		Type.NET_LABEL: return "LBL"
		Type.JUNCTION: return "J"
	return "X"

func clone() -> RefCounted:
	var c = get_script().new(id, type, position, value)
	c.rotation_deg = rotation_deg
	c.display_label = display_label
	c.is_virtual = is_virtual
	return c
