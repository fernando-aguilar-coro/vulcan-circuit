extends Node

func _ready() -> void:
	var out = "=== TEST 1: DIPOLE PLACER WITH AI COORDINATES ===\n"
	var text = """* positions
N0 0,4 ; N1 0,2 ; N2 2,2 ; N3 4,2 ; N4 2,4
* Fuente de voltaje de 10 V (nodo 1 positivo, nodo 0 negativo)
V1 1 0 DC 10V
* Fuente de corriente superior de 10 A (nodo 1 positivo, nodo 3 negativo)
I1 1 3 DC 10A
* Resistor de 5 ohms entre nodo 1 y nodo 3
R1 1 3 5
* Resistor de 2 ohms entre nodo 1 y nodo 2
R2 1 2 2
* Fuente de voltaje de 6 V entre nodo 2 y nodo 3 (nodo 2 negativo, nodo 3 positivo)
V2 2 3 DC 6V
* Resistor de 2 ohms entre nodo 2 y nodo 4
R3 2 4 2
* Fuente de corriente de 6 A entre nodo 4 y nodo 2 (nodo 4 negativo, nodo 2 positivo)
I2 4 2 DC 6
* Resistor de 4 ohms entre nodo 3 y nodo 4
R4 3 4 4"""

	var res = CircuitReconstructor.parse_and_build(text)
	out += "SUCCESS: %s\n" % str(res.success)
	for cid in res.components:
		var c: CircuitComponent = res.components[cid]
		out += "Comp [%s] Type: %s, Pos: %s, Rot: %d, Val: %s\n" % [c.id, c.type, str(c.position), c.rotation_deg, c.value]
	out += "Wires count: %d\n" % res.wires.size()

	var spice1 = CircuitGraph.generate_ngspice_netlist("Circuit1", res.components, res.wires)
	out += "SPICE 1 Warnings: %s\n" % str(spice1.warnings)
	out += "SPICE 1 Errors: %s\n" % str(spice1.errors)

	out += "\n=== TEST 2: NETLABELS (+5V, -5V, GND) ===\n"
	var text_labels = """* positions
N0 0,2 ; N1 0,0 ; N2 2,0
* label N1 +5V
* label N2 -5V
R1 +5V 0 10k
R2 -5V 0 4.7k"""
	var res2 = CircuitReconstructor.parse_and_build(text_labels)
	out += "SUCCESS 2: %s\n" % str(res2.success)
	for cid in res2.components:
		var c: CircuitComponent = res2.components[cid]
		out += "Comp [%s] Type: %s, Pos: %s, Rot: %d, Val: %s\n" % [c.id, c.type, str(c.position), c.rotation_deg, c.value]
	out += "Wires count 2: %d\n" % res2.wires.size()

	var spice2 = CircuitGraph.generate_ngspice_netlist("Circuit2_Labels", res2.components, res2.wires)
	out += "SPICE 2 Warnings: %s\n" % str(spice2.warnings)
	out += "SPICE 2 Errors: %s\n" % str(spice2.errors)
	out += "SPICE 2 Node Map: %s\n" % str(spice2.node_map)

	out += "\n=== TEST 3: MULTIPLE SOURCES (DUAL POWER RAILS + FLOATING SOURCE) ===\n"
	var text_multi = """* positions
N0 0,3 ; N1 0,1 ; N2 2,1 ; N3 4,1 ; N5 2,3
* Dual Supply: +10V rail and +5V rail
V1 1 0 DC 10V
V_aux 5 0 DC 5V
* Floating source between mesh nodes 2 and 3
V_float 2 3 DC 6V
* Mesh components
R1 1 2 1k
R2 2 3 2.2k
R3 3 5 4.7k
R4 5 0 10k"""
	var res3 = CircuitReconstructor.parse_and_build(text_multi)
	out += "SUCCESS 3: %s\n" % str(res3.success)
	for cid in res3.components:
		var c: CircuitComponent = res3.components[cid]
		out += "Comp [%s] Type: %s, Pos: %s, Rot: %d, Val: %s\n" % [c.id, c.type, str(c.position), c.rotation_deg, c.value]
	var spice3 = CircuitGraph.generate_ngspice_netlist("Circuit3_Multi", res3.components, res3.wires)
	out += "SPICE 3 Warnings: %s\n" % str(spice3.warnings)
	out += "SPICE 3 Errors: %s\n" % str(spice3.errors)
	out += "SPICE 3 Node Map: %s\n" % str(spice3.node_map)
	out += "\n--- NETLIST 3 ---\n" + spice3.netlist_text + "\n"

	out += "\n=== TEST 4: BJT TRANSISTOR (NPN SWITCH AMPLIFIER) ===\n"
	var text_bjt = """* positions
N0 0,4 ; N1 0,0 ; N2 0,2 ; N3 2,2 ; N4 2,1
* Power Supply: +12V rail and +3.3V input rail
Vcc 1 0 DC 12V
Vin 2 0 DC 3.3V
* Collector pull-up resistor from +12V (N1) to collector (N4)
Rc 1 4 1k
* Base current limiting resistor from input (N2) to base (N3)
Rb 2 3 10k
* NPN Transistor: Q1 <Collector=4> <Base=3> <Emitter=0> 2N2222
Q1 4 3 0 2N2222"""

	var res4 = CircuitReconstructor.parse_and_build(text_bjt)
	out += "SUCCESS 4: %s\n" % str(res4.success)
	for cid in res4.components:
		var c: CircuitComponent = res4.components[cid]
		out += "Comp [%s] Type: %s, Pos: %s, Rot: %d, Val: %s\n" % [c.id, c.type, str(c.position), c.rotation_deg, c.value]
	out += "Wires count 4: %d\n" % res4.wires.size()
	for w in res4.wires:
		out += "  Wire [%s] from %s to %s (Waypoints: %d)\n" % [w.id, w.from_pin_id, w.to_pin_id, w.waypoints.size()]

	var spice4 = CircuitGraph.generate_ngspice_netlist("Circuit4_BJT", res4.components, res4.wires)
	out += "SPICE 4 Warnings: %s\n" % str(spice4.warnings)
	out += "SPICE 4 Errors: %s\n" % str(spice4.errors)
	out += "SPICE 4 Node Map: %s\n" % str(spice4.node_map)
	out += "\n--- NETLIST 4 ---\n" + spice4.netlist_text + "\n"

	out += "\n=== TEST 5: PNP TRANSISTOR (HIGH-SIDE SWITCH) ===\n"
	var text_pnp = """* positions
N0 0,4 ; N1 0,0 ; N2 0,2 ; N3 2,2 ; N4 2,3
* Power Supply: +5V
Vcc 1 0 DC 5V
Vin 2 0 DC 0V
* High-side PNP switch: Q2 <Collector=4> <Base=3> <Emitter=1> 2N2907
Q2 4 3 1 2N2907
* Base drive resistor
Rb 2 3 4.7k
* Collector load to ground
Rload 4 0 1k"""

	var res5 = CircuitReconstructor.parse_and_build(text_pnp)
	out += "SUCCESS 5: %s\n" % str(res5.success)
	for cid in res5.components:
		var c: CircuitComponent = res5.components[cid]
		out += "Comp [%s] Type: %s, Pos: %s, Rot: %d, Val: %s\n" % [c.id, c.type, str(c.position), c.rotation_deg, c.value]
	out += "Wires count 5: %d\n" % res5.wires.size()
	for w in res5.wires:
		out += "  Wire [%s] from %s to %s (Waypoints: %d)\n" % [w.id, w.from_pin_id, w.to_pin_id, w.waypoints.size()]

	var spice5 = CircuitGraph.generate_ngspice_netlist("Circuit5_PNP", res5.components, res5.wires)
	out += "SPICE 5 Warnings: %s\n" % str(spice5.warnings)
	out += "SPICE 5 Errors: %s\n" % str(spice5.errors)
	out += "SPICE 5 Node Map: %s\n" % str(spice5.node_map)
	out += "\n--- NETLIST 5 ---\n" + spice5.netlist_text + "\n"

	print(out)
	var f = FileAccess.open("res://test_output.txt", FileAccess.WRITE)
	if f:
		f.store_string(out)
		f.close()
	var f2 = FileAccess.open("C:/fer/protoAI/protoAI/project/test_output.txt", FileAccess.WRITE)
	if f2:
		f2.store_string(out)
		f2.close()
	get_tree().quit()
