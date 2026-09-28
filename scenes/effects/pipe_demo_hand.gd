extends Node3D

## Stand-in for a hand in the pipe demo, for HandDissolve: holding the right
## mouse button pushes it through the wall under the cursor, so a hole burns
## there; otherwise it stays at the camera, out of every wall.

@export var camera: Camera3D

## How far past the surface the hand goes, in meters.
@export var reach := 0.3

## Physics layers of the walls.
@export_flags_3d_physics var collision_mask := 1


func _physics_process(_delta: float) -> void:
	global_position = camera.global_position
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * 100.0, collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position + direction * reach
