class_name CanvasCamera
extends RefCounted

## CanvasCamera: Manages viewport transforms, grid coordinates, and GPU grid shader.

const GRID_SIZE: float = 20.0
const COLOR_BG: Color = Color(0.09, 0.1, 0.13, 1.0)
const COLOR_GRID: Color = Color(0.18, 0.2, 0.26, 0.7)

var pan_offset: Vector2 = Vector2(300, 200)
var zoom_level: float = 1.0
var grid_material: ShaderMaterial = null

func _init() -> void:
	_init_grid_material()

func _init_grid_material() -> void:
	var shader = Shader.new()
	shader.code = """shader_type canvas_item;

uniform vec2 pan_offset = vec2(300.0, 200.0);
uniform float zoom_level = 1.0;
uniform vec4 bg_color : source_color = vec4(0.09, 0.1, 0.13, 1.0);
uniform vec4 grid_color : source_color = vec4(0.18, 0.2, 0.26, 0.7);
uniform float grid_size = 20.0;

void fragment() {
	vec2 world_pos = (VERTEX - pan_offset) / zoom_level;
	vec2 grid_offset = mod(world_pos + grid_size * 0.5, grid_size) - grid_size * 0.5;
	float dist_screen = length(grid_offset) * zoom_level;
	float dot_radius = clamp(zoom_level * 1.15, 1.0, 2.0);
	float alpha = 1.0 - smoothstep(dot_radius - 0.75, dot_radius + 0.75, dist_screen);
	COLOR = mix(bg_color, grid_color, alpha * grid_color.a);
}
"""
	grid_material = ShaderMaterial.new()
	grid_material.shader = shader
	grid_material.set_shader_parameter("bg_color", COLOR_BG)
	grid_material.set_shader_parameter("grid_color", COLOR_GRID)
	grid_material.set_shader_parameter("grid_size", GRID_SIZE)
	update_material_params()

func update_material_params() -> void:
	if grid_material:
		grid_material.set_shader_parameter("pan_offset", pan_offset)
		grid_material.set_shader_parameter("zoom_level", zoom_level)

func screen_to_world(screen_pos: Vector2) -> Vector2:
	return (screen_pos - pan_offset) / zoom_level

func world_to_screen(world_pos: Vector2) -> Vector2:
	return world_pos * zoom_level + pan_offset

func snap_to_grid(world_pos: Vector2) -> Vector2:
	var gx = round(world_pos.x / GRID_SIZE) * GRID_SIZE
	var gy = round(world_pos.y / GRID_SIZE) * GRID_SIZE
	return Vector2(gx, gy)

func zoom_at(screen_pos: Vector2, factor: float) -> bool:
	var new_zoom = clamp(zoom_level * factor, 0.3, 3.5)
	if new_zoom == zoom_level:
		return false
	var mouse_world = screen_to_world(screen_pos)
	zoom_level = new_zoom
	pan_offset = screen_pos - mouse_world * zoom_level
	update_material_params()
	return true

func pan_by(delta: Vector2) -> void:
	pan_offset += delta
	update_material_params()

func update_pan(new_pan: Vector2) -> void:
	pan_offset = new_pan
	update_material_params()
