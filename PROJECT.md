# Project: ProtoAI EDA - XSPICE Digital Logic Gates & Reactive Telemetry HUD

## Architecture
- **MVI Pattern**: Strictly unidirectional data flow:
  `UI / Ticker` -> `CircuitIntent` -> `CircuitStore.dispatch` -> `Domain Reducers` -> `CircuitState.clone()` -> `state_changed` -> `UI Views (_render_state)`.
- **Canvas Rendering**: Immediate-mode 2D drawing via Godot 4 `_draw()`, transformed by camera pan/zoom matrix. Components delegate to modular renderers with local-to-world transform closures `tf`.
- **Corner Telemetry HUD**: Mobile-style glassmorphic overlay `Control` mounted directly on `SchematicCanvas` (anchored to top-right viewport space), updating reactively on `set_state(new_state)` without camera jitter.
- **Simulation Engine**: ngspice-34 DLL via GDExtension `CircuitSimulator`, with `digital.cm` code model loaded for XSPICE digital logic gates (`d_and`, `d_or`, `d_inverter`, `d_nand`, `d_nor`, `d_xor`).

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| F1 | Logic Gate Component Models | Add AND, OR, NOT, NAND, NOR, XOR to `CircuitComponent.Type`, set prefix "A", default values, and library catalog | M1 | ORIGINAL_REQUEST §R1 |
| F2 | 20px Grid Pin Layout | Define grid-aligned terminal pins in `ComponentPinFactory.gd` (`(-40, ±20)`, `(40, 0)` for binary gates; `(-40, 0)`, `(40, 0)` for NOT) | M1 | ORIGINAL_REQUEST §R1 |
| F3 | XSPICE Netlist Export & Code Models | Emit valid XSPICE syntax (`a<id> [in1 in2] out <model>` for binary, `a<id> in out <model>` for NOT), model lines, and ensure `digital.cm` loading | M1 | ORIGINAL_REQUEST §R1 |
| F4 | IEEE/ANSI Symbol Renderers | Implement distinctive shape rendering (arcs, Bézier curves, inversion bubbles, lead lines) for all 6 gates in `LogicGateRenderer.gd` | M2 | ORIGINAL_REQUEST §R1 |
| F5 | Canvas Placement & Toolbar Integration | Add gates to toolbar/palette, handle placement tool, rotation (0/90/180/270°), mirroring, selection, and wiring | M2 | ORIGINAL_REQUEST §R1 |
| F6 | Telemetry State & Periodic Loop | Add telemetry state, calculations (V, I, P, R, digital 0/1), and non-blocking ~16ms update tick loop via `CircuitIntent` | M3 | ORIGINAL_REQUEST §R2 |
| F7 | Reactive Canvas Telemetry HUD | Implement corner overlay `Control` (`CanvasTelemetryHud`) displaying live electrical & digital metrics on component selection | M3 | ORIGINAL_REQUEST §R2 |
| F8 | E2E Test Suite Pass (Tiers 1-4) | Verify 100% pass on feature coverage, boundaries, pairwise combinations, and real-world application scenarios | M4 | ORIGINAL_REQUEST §Acceptance |
| F9 | Adversarial Coverage Hardening (Tier 5) | White-box adversarial testing, stress testing, and edge case hardening | M4 | Project Pattern §Final Milestone |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Core Logic Gates & XSPICE Netlist | Component types, 20px grid pins, SPICE emitter (array/scalar syntax), `digital.cm` integration | none | PLANNED |
| M2 | IEEE/ANSI Symbol Rendering & Canvas UI | `LogicGateRenderer`, `ComponentRenderer` delegation, placement tool, rotation, mirroring, toolbar/catalog | M1 | PLANNED |
| M3 | Reactive Telemetry Engine & HUD | Non-blocking ~16ms sampling loop, MVI telemetry intent, `CanvasTelemetryHud` corner overlay | M1, M2 | PLANNED |
| M4 | Final Milestone: E2E Test Suite & Hardening | Phase 1: Pass 100% of E2E tests (Tiers 1-4). Phase 2: Adversarial Coverage Hardening (Tier 5) | M1, M2, M3, E2E Track | PLANNED |

## Interface Contracts
### 1. `CircuitComponent` ↔ `ComponentPinFactory`
- `CircuitComponent.Type`: `GATE_AND`, `GATE_OR`, `GATE_NOT`, `GATE_NAND`, `GATE_NOR`, `GATE_XOR`.
- Pins:
  - Binary gates (`AND`, `OR`, `NAND`, `NOR`, `XOR`): `in1` at `Vector2(-40, -20)`, `in2` at `Vector2(-40, 20)`, `out` at `Vector2(40, 0)`.
  - NOT gate: `in` at `Vector2(-40, 0)`, `out` at `Vector2(40, 0)`.
- All pin coordinates are exact multiples of `GRID_SIZE = 20.0`.

### 2. `SpiceNetlistEmitter` ↔ `CircuitSimulator`
- Array input for binary gates: `a<id> [<n_in1> <n_in2>] <n_out> <model>` with `.model <model> d_<gate>`.
- Scalar input for inverter: `a<id> <n_in> <n_out> <model>` with `.model <model> d_inverter`.
- Simulator initialization: ensures `codemodel C:/Spice64/Spice64_dll/lib/ngspice/digital.cm` is executed so `d_*` code models are recognized.
- Output probing: for digital gates driving high-impedance or unloaded nets, a probe resistor to ground ensures ngspice outputs voltage in `.op`.

### 3. `ComponentRenderer` ↔ `LogicGateRenderer`
- `LogicGateRenderer.draw_gate(canvas: CanvasItem, comp: CircuitComponent, tf: Callable, is_selected: bool, hovered_pin_id: String, font: Font, pal: Dictionary) -> void`
- Uses transform closure `tf(local: Vector2) -> Vector2` to ensure proper rotation and mirroring.

### 4. `CircuitStore` ↔ `CanvasTelemetryHud`
- `CircuitIntent.create_update_telemetry(metrics: Dictionary) -> CircuitIntent`
- `CircuitState.telemetry_data`: Holds dictionary keyed by component ID or active selection with keys:
  - `v_drop`: float (Volts)
  - `current`: float (Amperes)
  - `power`: float (Watts)
  - `resistance`: float (Ohms, optional)
  - `logic_state`: String or int ("0", "1", "UNDEFINED")
  - `pin_states`: Dictionary of pin_name -> logic level
- `CanvasTelemetryHud.set_state(new_state: CircuitState)`: updates overlay UI reactively without rebuilding node hierarchy.

## Code Layout
- `project/src/core/model/circuit_component.gd`: Gate enum constants and prefixes
- `project/src/core/model/component_pin_factory.gd`: Gate pin positioning
- `project/src/core/graph/spice_netlist_emitter.gd`: XSPICE netlist syntax emission
- `project/src/core/state/circuit_intent.gd`: Telemetry intents
- `project/src/core/state/circuit_state.gd`: Telemetry data fields
- `project/src/core/state/circuit_store.gd`: Telemetry dispatching & simulator code model setup
- `project/src/core/state/reducers/simulation_reducer.gd`: Telemetry calculation logic
- `project/src/features/schematic_canvas/renderers/logic_gate_renderer.gd`: IEEE/ANSI symbol drawing
- `project/src/features/schematic_canvas/renderers/component_renderer.gd`: Integration of logic gate renderer
- `project/src/features/schematic_canvas/hud/canvas_telemetry_hud.gd`: Overlay HUD Control
- `project/src/features/schematic_canvas/schematic_canvas.gd`: Mounting and updating HUD
- `project/src/ui/shell/device_library_catalog.gd`: Catalog entries for logic gates
- `project/tests/`: Headless Godot test scenes and scripts
