# Test Infrastructure Specification: Logic Gates & Canvas Telemetry HUD

## 1. Test Philosophy

### 1.1 Opaque-Box & Requirement-Driven Methodology
The E2E test suite validates the ProtoAI EDA application strictly through observable interfaces and behavioral contracts derived directly from user requirements (`ORIGINAL_REQUEST.md` §R1, §R2, §R3) and project specifications (`PROJECT.md`). Tests exercise:
- Component model creation, type classification, and prefix assignment.
- Spatial pin geometry, grid snapping adherence (20px standard), and coordinate transformation under rotation/mirroring.
- Netlist graph synthesis and ngspice/XSPICE string emission syntax.
- Live analog and digital electrical simulation results via ngspice/XSPICE with `digital.cm`.
- MVI state immutability, intent dispatching, and unidirectional data flow.
- Reactive UI overlay presentation (`CanvasTelemetryHud`) and telemetry metric formatting.

Tests do not couple to transient internal private methods or implementation details.

### 1.2 4-Tier Progressive Test Methodology
The test suite is structured into four distinct hierarchical tiers:
1. **Tier 1 — Feature Coverage**: Comprehensive verification of primary behavior (happy path) for all 7 features (F1 to F7), guaranteeing at least 5 isolated test cases per feature.
2. **Tier 2 — Boundary & Corner Cases**: Stress-testing edge cases, floating terminals, inverted logic levels, extreme voltages/impedances, null selections, and high-frequency intent emissions.
3. **Tier 3 — Cross-Feature Combinations**: Validating interoperability between analog and digital domains, multi-gate cascades, active simulation loop interactions, and concurrent telemetry updates.
4. **Tier 4 — Real-World Application Scenarios**: End-to-end circuit synthesis and simulation of industry-standard digital and mixed-signal circuits (Half Adder, Full Adder, SR Latch, 2-to-1 Multiplexer, and Mixed-Signal Window Comparator).

### 1.3 Progressive Testability & Graceful Reporting
To support development across milestones (M1 through M4):
- The test runner dynamically probes feature availability (e.g. checking if enum constants exist in `CircuitComponent.Type`, if `CanvasTelemetryHud` is instantiated, or if XSPICE code models are active).
- When a feature is not yet implemented, the runner logs a clear, non-fatal feature deficiency failure (`FEATURE_NOT_IMPLEMENTED`), records metrics, and proceeds to the remaining tests without crashing the Godot GDScript parser or engine runtime.
- Test runs produce structured console output and write persistent machine-readable logs to `project/e2e_test_results.txt`.

---

## 2. Feature Inventory (F1 – F7 Mapping)

| Feature ID | Description | Source | Primary Verification Target |
|---|---|---|---|
| **F1** | Logic Gate Component Models | ORIGINAL_REQUEST §R1, PROJECT §F1 | `CircuitComponent.Type`: `GATE_AND`, `GATE_OR`, `GATE_NOT`, `GATE_NAND`, `GATE_NOR`, `GATE_XOR`; SPICE prefix `"A"`; Catalog entries |
| **F2** | 20px Grid Pin Layout | ORIGINAL_REQUEST §R1, PROJECT §F2 | Binary gates: `(-40, -20)`, `(-40, 20)`, `(40, 0)`; NOT: `(-40, 0)`, `(40, 0)`; all pins on 20px grid multiples |
| **F3** | XSPICE Netlist Export & Code Models | ORIGINAL_REQUEST §R1, PROJECT §F3 | Vector syntax `a<id> [in1 in2] out <model>` for binary gates; scalar syntax `a<id> in out <model>` for NOT; `.model` declarations; `digital.cm` |
| **F4** | IEEE/ANSI Symbol Renderers | ORIGINAL_REQUEST §R1, PROJECT §F4 | Visual contour dispatching, lead lines, inversion bubbles, rotation & mirroring transform closures |
| **F5** | Canvas Placement & Toolbar Integration | ORIGINAL_REQUEST §R1, PROJECT §F5 | Placement intents, 90/180/270° rotations, horizontal mirroring, terminal wire connections |
| **F6** | Telemetry State & Periodic Loop | ORIGINAL_REQUEST §R2, PROJECT §F6 | Live V, I, P, R, digital 0/1 calculations; `CircuitIntent.IntentType.UPDATE_TELEMETRY`; non-blocking ~16ms loop |
| **F7** | Reactive Canvas Telemetry HUD | ORIGINAL_REQUEST §R2, PROJECT §F7 | Corner overlay Control `CanvasTelemetryHud`; glassmorphic card; reactive `set_state` updates without node rebuild |

---

## 3. Test Architecture

### 3.1 Test Execution & Headless Runner Command
The test suite is packaged as a standalone headless Godot 4 test runner script and scene:
- Script: `res://tests/test_e2e_logic_and_telemetry.gd` (`project/tests/test_e2e_logic_and_telemetry.gd`)
- Scene: `res://tests/test_e2e_logic_and_telemetry_scene.tscn` (`project/tests/test_e2e_logic_and_telemetry_scene.tscn`)

Runner command:
```powershell
powershell -Command "Start-Process -FilePath 'C:\Users\USUARIO\Desktop\Godot_v4.7-stable_win64.exe' -ArgumentList '--headless','--path','c:\fer\protoAI\protoAI\project','res://tests/test_e2e_logic_and_telemetry_scene.tscn' -Wait -NoNewWindow"
```

### 3.2 Output Logging & Test Artifacts
During execution, the test suite logs every test result to Godot stdout and simultaneously writes a detailed summary report to:
`c:\fer\protoAI\protoAI\project\e2e_test_results.txt`

### 3.3 Assertion Strategy & Pass/Fail Semantics
The test framework provides strict, descriptive assertions:
- `assert_true(condition: bool, message: String) -> bool`
- `assert_false(condition: bool, message: String) -> bool`
- `assert_eq(actual: Variant, expected: Variant, message: String) -> bool`
- `assert_approx_eq(actual: float, expected: float, tolerance: float, message: String) -> bool`
- `assert_contains(text: String, substring: String, message: String) -> bool`
- `assert_not_contains(text: String, substring: String, message: String) -> bool`
- `assert_feature_supported(feature_name: String, available: bool) -> bool`

Pass/Fail Criteria:
- **PASS**: All assertions within the test case succeed.
- **FAIL**: Any assertion within the test case fails. Failure message details expected vs actual value.
- The test harness aggregates total runs, passes, failures, and skips per tier, computing overall pass rate.

---

## 4. Real-World Application Scenarios (Tier 4)

1. **RW1: 1-Bit Half Adder**
   - Inputs: $A$, $B$
   - Components: 1 XOR gate, 1 AND gate
   - Logic: $\text{Sum} = A \oplus B$, $\text{Carry} = A \cdot B$
   - Verification: All 4 input combinations $(0,0 \to 0,0)$, $(0,1 \to 1,0)$, $(1,0 \to 1,0)$, $(1,1 \to 0,1)$ validated for correct node voltages and logic states.

2. **RW2: 1-Bit Full Adder**
   - Inputs: $A$, $B$, $C_{in}$
   - Components: 2 XOR gates, 2 AND gates, 1 OR gate
   - Logic: $\text{Sum} = A \oplus B \oplus C_{in}$, $C_{out} = (A \cdot B) + (C_{in} \cdot (A \oplus B))$
   - Verification: Full 8-state truth table verified through cascading event nets.

3. **RW3: Bistable Set-Reset (SR) Latch**
   - Inputs: $S$ (Set), $R$ (Reset)
   - Components: 2 cross-coupled NOR gates (or NAND gates with active-low inputs)
   - Logic: $Q = \overline{R + \bar{Q}}$, $\bar{Q} = \overline{S + Q}$
   - Verification: Set state $(S=1, R=0 \implies Q=1)$, Reset state $(S=0, R=1 \implies Q=0)$, and Memory Hold $(S=0, R=0 \implies Q_{prev})$.

4. **RW4: 2-to-1 Multiplexer (MUX)**
   - Inputs: Data lines $D_0$, $D_1$, Selection line $S$
   - Components: 1 NOT gate, 2 AND gates, 1 OR gate
   - Logic: $Y = (D_0 \cdot \overline{S}) + (D_1 \cdot S)$
   - Verification: Output follows $D_0$ when $S=0$, follows $D_1$ when $S=1$.

5. **RW5: Mixed-Signal Window Comparator with Logic Detector**
   - Inputs: Analog voltage input $V_{in}$, reference rails $V_{ref\_low} = 2.0\text{V}$, $V_{ref\_high} = 4.0\text{V}$
   - Components: Analog voltage divider, 2 OpAmps/Comparators, 1 NOT gate, 1 AND gate
   - Logic: In-Window condition $(V_{ref\_low} < V_{in} < V_{ref\_high})$ produces digital logic HIGH ($1 / 3.3\text{V}$), out-of-window produces LOW ($0 / 0.0\text{V}$).
   - Verification: Validates analog-to-digital auto-ADC bridging, digital gate processing, and analog telemetry probing.

---

## 5. Coverage Thresholds & Target Counts

| Tier | Category | Minimum Required | Planned In Suite |
|---|---|---|---|
| **Tier 1** | Feature Coverage (F1–F7: AND, OR, NOT, NAND, NOR, XOR, Telemetry HUD) | $\ge 5$ per feature (35 total) | 37 tests |
| **Tier 2** | Boundary & Corner Cases (floating pins, extreme values, null selection, rapid clicks) | $\ge 5$ per feature domain (10 total) | 12 tests |
| **Tier 3** | Cross-Feature Combinations (A/D bridges, cascades, active simulation switching) | $\ge 5$ pairwise combinations | 6 tests |
| **Tier 4** | Real-World Application Circuits (Half Adder, Full Adder, SR Latch, MUX, Window Comp) | $\ge 5$ realistic circuits | 5 circuits (15 sub-cases) |
| **Total** | Full E2E Test Suite | **$\ge 55$ test assertions** | **60 test cases** |
