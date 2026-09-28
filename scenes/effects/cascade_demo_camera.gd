extends Camera3D

## Orbit camera for the cascade demo: drag with the left mouse button to turn
## around what is in focus, scroll to zoom, and press 1 to 9 to focus the
## matching entry of [member focus_points]. A [Cascade] in focus is framed
## around the middle of its fall.

## What the number keys focus, in order; the first is focused at start.
@export var focus_points: Array[Node3D] = []

## Distance from the focus, in meters.
@export var distance := 10.0
@export var min_distance := 1.5
@export var max_distance := 40.0

## Degrees turned per pixel dragged.
@export var sensitivity := 0.25

## How quickly the camera glides to a new focus, per second.
@export var glide_speed := 4.0

var _yaw := 0.0
var _pitch := -12.0
var _focus := Vector3.ZERO
var _target := Vector3.ZERO


func _ready() -> void:
	if not focus_points.is_empty():
		_target = _focus_of(focus_points[0])
		_focus = _target


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= motion.relative.x * sensitivity
		_pitch = clampf(_pitch - motion.relative.y * sensitivity, -85.0, 85.0)
		return

	var button := event as InputEventMouseButton
	if button and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(distance / 1.1, min_distance)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(distance * 1.1, max_distance)
		return

	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		var index := key.keycode - KEY_1
		if index >= 0 and index < focus_points.size():
			_target = _focus_of(focus_points[index])


func _process(delta: float) -> void:
	_focus = _focus.lerp(_target, 1.0 - exp(-glide_speed * delta))
	var direction := Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0)) * Vector3.BACK
	global_position = _focus + direction * distance
	look_at(_focus)


static func _focus_of(node: Node3D) -> Vector3:
	if node is Cascade:
		return (node.global_position + (node as Cascade).landing_point()) / 2.0
	return node.global_position
