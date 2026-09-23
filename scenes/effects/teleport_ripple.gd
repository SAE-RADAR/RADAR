extends Node

## Spawns a water ripple on the floor wherever the player lands after a teleport.

const WaterRipple := preload("res://scenes/effects/water_ripple.tscn")

## Player body whose teleports trigger a ripple.
@export var player_body: XRToolsPlayerBody

## Physics layers treated as floor when placing the ripple.
@export_flags_3d_physics var floor_mask := 1

## Height above the floor, to avoid z-fighting with the scan.
@export var surface_offset := 0.005


func _ready() -> void:
	if player_body:
		player_body.player_teleported.connect(_on_player_teleported)


## Spawns a ripple on the floor below [param position].
func spawn_at(position: Vector3, up := Vector3.UP) -> void:
	var normal := up
	var query := PhysicsRayQueryParameters3D.create(position + up * 0.5, position - up * 1.0, floor_mask)
	if player_body:
		query.exclude = [player_body.get_rid()]
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		position = hit.position
		normal = hit.normal

	var ripple: Node3D = WaterRipple.instantiate()
	add_child(ripple)
	ripple.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, normal)), position + normal * surface_offset)


func _on_player_teleported(_delta_transform: Transform3D) -> void:
	spawn_at(player_body.global_position, player_body.up_player)
