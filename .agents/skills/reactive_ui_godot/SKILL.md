---
name: reactive_ui_godot
description: Technical guide for authoring and mounting React-style Reactive UI components (.guitkx) in Godot 4.
---

# Reactive UI (React for Godot) Technical Cheatsheet

## 1. Syntax & Declaration (.guitkx)
* **File extension:** `.guitkx` (auto-compiles to sibling `.gd`).
* **Component declaration:** Use plain function declarations with return type hint `-> RUIVNode`.
  ```guitkx
  export AppUI() -> RUIVNode {
      var count = useState(0)
      return (
          <VBoxContainer style={ {"separation": 8} }>
              <Label text={"Count: %d" % count[0]} />
              <Button text="Add" onPressed={func(): count[1].call(count[0] + 1)} />
          </VBoxContainer>
      )
  }
  ```
  *(Note: `component Foo()` keyword wrapper is deprecated in v0.11+; use plain `export Foo() -> RUIVNode`).*

## 2. State & Hooks
* `useState(initial_value)` returns a 2-element Array `[value, setter_callable]`.
  * Read: `state_var[0]`
  * Set: `state_var[1].call(new_val)`
* Standard Hooks available: `useState`, `useEffect`, `useRef`, `useMemo`, `useCallback`, `useReducer`, `useContext`, `useSignal`.

## 3. Markup & Attributes
* **Host tags:** Match Godot `Control` node class names: `VBoxContainer`, `HBoxContainer`, `Label`, `Button`, `PanelContainer`, `MarginContainer`, `LineEdit`, `CheckButton`, `ProgressBar`, `Control`, etc.
* **Layout Presets:** Pass `anchors_preset` as a direct attribute (e.g. `<Control anchors_preset={15}>` where 15 is `Control.PRESET_FULL_RECT`).
* **Styles & Theme Overrides:** Passed via `style={ {...} }` dictionary attribute (for `margin_left`, `separation`, `custom_minimum_size`, `font_size`, theme colors), e.g.:
  * `style={ {"margin_left": 30, "margin_top": 30, "separation": 16} }`
* **Signal Handlers:** Use camelCase matching signal names (`onPressed`, `text_changed`, `toggled`).

## 4. Mounting in GDScript
To mount a top-level `.guitkx` component onto any node in GDScript:
```gdscript
extends Node

var _ui_root: ReactiveRoot

func _ready() -> void:
    # Mount ReactiveRoot and render the compiled component Callable
    _ui_root = ReactiveRoot.create(self, V.fc(V.comp("res://app_ui.gd"), {}))
```

## 5. Toolchain & Compilation
* Handled by `@tool EditorPlugin` (`res://addons/reactive_ui/plugin.gd`).
* Programmatic compilation: `RUIGuitkx.compile(source_string, "filename.guitkx")`.
* Diagnostics sidecar: `filename.guitkx.diags.json`.
