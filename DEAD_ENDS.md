# Dead Ends Log

| Iteration | Approach Tried | Why It Failed | Files Touched |
|-----------|---------------|---------------|---------------|
| Survey | Using bracketed array syntax for NOT/Inverter gate: `a<id> [in] out m_inv` | ngspice rejects with fatal error: `ERROR - Scalar connection expected, [ found` | spice_netlist_emitter.gd |
| Survey | Placing `codemodel ...` as netlist line starting with 'c' | ngspice parser treats line starting with 'c' as invalid capacitor instance; must execute via control or simulator execute_command | circuit_simulator.cpp / circuit_store.gd |
| Survey | Using .guitkx reactive UI framework | Framework not bundled in project runtime; native Godot Control nodes must be used | schematic_canvas/hud |
