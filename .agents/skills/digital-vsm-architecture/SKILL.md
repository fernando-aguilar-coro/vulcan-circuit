---
name: digital-vsm-architecture
description: Architectural specification, behavioral models, MVI integration, and development workflows for the Virtual System Modeling (VSM) digital simulation engine and university components (logic gates, decoders, flip-flops, 7-segment displays, memories).
---

# Digital VSM Architecture Skill

This skill documents the **Virtual System Modeling (VSM)** digital logic engine and component library for ProtoAI, designed to simulate educational and university-level digital electronics (logic gates, 74LS series ICs, flip-flops, counters, memories, and displays) while following **MVI (Model-View-Intent)** architecture.

---

## 1. Core Philosophy & Hybrid Simulation

1. **Separation of Concerns**:
   - **Analog Domain**: Handled by the C++ ngspice shared library wrapper (`CircuitSimulator`). Pure analog components (R, L, C, Diodes, BJTs, Op-Amps, Sources) are emitted to the SPICE netlist deck.
   - **Digital Domain**: Handled natively by the GDScript **VSM Discrete Simulator** (`DigitalVsmEngine`). Pure digital components (Gates, 74LS47, 7-Segment Displays, Flip-Flops) are **omitted from the raw SPICE deck**, avoiding ngspice `cannot be both analog and digital` convergence errors.
2. **Mixed-Signal Bridges**:
   - **A/D Bridge**: Analog node voltages $> 1.65\text{ V}$ translate to `LogicState.HIGH (1)`; voltages $\le 1.65\text{ V}$ translate to `LogicState.LOW (0)`.
   - **D/A Bridge**: Digital outputs connected to analog loads emit a DC voltage source ($3.3\text{ V}$ or $0\text{ V}$) into the SPICE deck.

---

## 2. 4-State Discrete Logic & Proteus ISIS Conventions

The VSM engine evaluates discrete nets using a 4-state logic model matching Proteus ISIS visual conventions:

| State | Level Value | Proteus Color | Hex Code | Visual Indicator | Description |
| :--- | :---: | :--- | :--- | :--- | :--- |
| **LOW** | `0` | **Blue** | `#1F87E6` | $6\times 6\text{ px}$ square below pin | Driven low ($< 1.65\text{ V}$ or boolean `0`) |
| **HIGH** | `1` | **Red** | `#E63836` | $6\times 6\text{ px}$ square below pin | Driven high ($\ge 1.65\text{ V}$ or boolean `1`) |
| **FLOAT** | `2` | **Grey** | `#9E9E9E` | $6\times 6\text{ px}$ square below pin | High-impedance / unconnected floating pin |
| **CONTENTION** | `3` | **Yellow** | `#FFD600` | $6\times 6\text{ px}$ square below pin | Bus conflict / short circuit (opposing active drivers) |

- **Terminals & Wires**: Wire segments retain standard schematic coloring (normal/hover/selected) to prevent visual clutter. Circular terminal pins retain their standard circular connection radius.
- **Pin Square Indicators**: Only digital components display a $6\times 6\text{ px}$ logic square indicator positioned directly underneath each pin terminal.

---

## 3. Directory Layout & Modular Structure

```
project/src/core/vsm/
├── digital_vsm_engine.gd              # Orchestrator: multi-pass relaxation loop, contention resolution, mixed-signal bridge
├── digital_vsm_types.gd               # Standard types, LogicState enum, Proteus color tokens, voltage thresholds
└── library/
    ├── combinational/
    │   ├── gate_evaluator.gd          # Pure combinational truth tables for AND, OR, NOT, NAND, NOR, XOR, XNOR
    │   └── decoder_74ls47.gd          # BCD to 7-Segment Decoder/Driver (TTL 74LS47 active-low logic)
    ├── sequential/                    # Edge-triggered models (SR, D, JK, T Flip-Flops, Registers, 74LS90 Counters)
    ├── peripherals/
    │   └── seven_segment_evaluator.gd # Common Anode (CA) & Common Cathode (CC) 7-Segment display logic with DP
    └── memory/                        # Addressable memory models (RAM, ROM, EEPROM)

project/src/features/schematic_canvas/renderers/
├── component_renderer.gd              # Main dispatcher for component and terminal pin rendering
├── digital_gate_renderer.gd           # Procedural vector drawing for IEEE/ANSI logic gates and toggle inputs
└── seven_segment_renderer.gd          # Authentic vector drawing for LED 7-segment displays (a-g bars, DP dot, pin labels)
```

---

## 4. MVI (Model-View-Intent) Data Flow

All digital simulation operations strictly adhere to unidirectional data flow:

```
[ User Interaction ] ───▶ [ CircuitIntent ] ───▶ [ Pure Reducers ] ───▶ [ Immutable CircuitState ] ───▶ [ Views / Renderers ]
  - Pick from 'P' dialog     - SELECT_TOOL (PLACE_COMPONENT) - SelectionReducer      - pin_logic_states        - ComponentRenderer
  - Keyboard (R,L,C,Q)       - PLACE_COMPONENT               - ComponentReducer      - digital_node_states     - SevenSegmentRenderer
  - Click to Toggle Switch   - TOGGLE_LOGIC_STATE            - DigitalVsmReducer     - telemetry_data          - CanvasTelemetryHUD
```

### Component Placement Architecture:
- Selecting any component from the **Pick Devices (`P`) dialog** or the **DEVICES sidebar** must dispatch:
  ```gdscript
  CircuitIntent.create_select_tool(CircuitState.Tool.PLACE_COMPONENT, comp_type, default_val)
  ```
- This activates `PlaceToolState` on the canvas, displaying a cursor ghost preview that lets the user click to place components, rotate with `[R]`, mirror with `[E]`, and cancel back to selection mode with `[Right Click]` or `[Esc]`.

### Keyboard Shortcuts for Common Analog Components:
- `[R]`: Rotate selected element (if selection exists) OR activate Resistor placement tool.
- `[L]`: Activate Inductor placement tool.
- `[C]`: Activate Capacitor placement tool.
- `[Q]`: Activate BJT Transistor (NPN) placement tool.
- `[D]`: Activate Diode placement tool.
- `[W]`: Activate Wire routing tool.
- `[G]`: Activate Ground reference placement tool.
- `[V]`: Activate DC Voltage Source tool.
- `[I]`: Activate DC Current Source tool.

---

## 5. Step-by-Step Workflow: Adding a New University Component

To introduce a new digital component (e.g., **74LS76 Dual JK Flip-Flop** or **4-Bit Ripple Counter**):

### Step 1: Register Component Type
In [circuit_component.gd](file:///c:/fer/protoAI/protoAI/project/src/core/model/circuit_component.gd):
- Add the new enum entry to `CircuitComponent.Type` (e.g. `IC_74LS76`).
- Add its prefix in `get_spice_prefix()` (`"U"` for ICs, `"DSP"` for displays).
- Define its bounding box in `get_bounding_box()`.

### Step 2: Define Grid-Aligned Pins
In [component_pin_factory.gd](file:///c:/fer/protoAI/protoAI/project/src/core/model/component_pin_factory.gd):
- Add a setup case under `setup_component()`.
- Ensure all pin coordinates strictly adhere to exact multiples of the **20px schematic grid** (`x` and `y` $\in \{ \dots, -40, -20, 0, 20, 40, \dots \}$).
- Set `comp.ic_box_size` and appropriate pin labels.

### Step 3: Implement Behavioral Evaluator
In `project/src/core/vsm/library/<category>/`:
- Create a pure RefCounted class (e.g., `jk_flip_flop.gd` or `counter_74ls90.gd`).
- Read pin inputs from `pin_inputs: Dictionary` where values are `DigitalVsmEngine.LogicState`.
- Evaluate outputs and internal sequential states.
- Return output pin states dictionary and telemetry metadata.

### Step 4: Register in VSM Engine
In [digital_vsm_engine.gd](file:///c:/fer/protoAI/protoAI/project/src/core/vsm/digital_vsm_engine.gd):
- Add the component type to `is_digital_component()`.
- In `evaluate()`, read its input nodes, call the behavioral evaluator, assign output pin states, and register output nodes in `node_driver_values` via `_register_driver()`.

### Step 5: Implement Visual Vector Drawing
In `project/src/features/schematic_canvas/renderers/`:
- If an IC, use `ActiveRenderer.draw_ic()` with custom pin labels.
- If a custom peripheral (like a display), create a dedicated renderer closure using `tf.call(local_coord)`.
- Connect drawing in `ComponentRenderer.draw_component()`.

### Step 6: Add to Device Catalog
In [device_library_catalog.gd](file:///c:/fer/protoAI/protoAI/project/src/ui/shared/device_library_catalog.gd):
- Add the entry under `Category.DIGITAL` with `tool: CircuitState.Tool.PLACE_COMPONENT`.

### Step 7: Add Automated Headless Test
In [test_m1_logic_gates_model_and_netlist.gd](file:///c:/fer/protoAI/protoAI/project/tests/test_m1_logic_gates_model_and_netlist.gd):
- Add assertions verifying truth table, edge triggering, and telemetry under toggle transitions.
- Execute via headless Godot runner:
  ```powershell
  Start-Process -FilePath 'C:\Users\USUARIO\Desktop\Godot_v4.7-stable_win64.exe' -ArgumentList '--headless','--path','c:\fer\protoAI\protoAI\project','res://tests/test_m1_logic_gates_model_and_netlist_scene.tscn' -Wait -NoNewWindow
  ```
