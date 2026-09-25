extends Node

## Dissolves the scan outward from where a hand goes through it, and rebuilds
## it once the hand comes back out.
##
## A hand counts as "through" when the line from the head to the hand crosses
## the scan and the hand is past the surface by at least [member min_penetration].

const DissolveShader := preload("res://scenes/world/scan_dissolve.gdshader")

## Node holding the scanned meshes to dissolve.
@export var scan: Node3D
@export var camera: XRCamera3D
@export var left_hand: XRController3D
@export var right_hand: XRController3D

## Physics layers of the scan's collision.
@export_flags_3d_physics var collision_mask := 1

## How far past the surface the hand must be, so brushing a wall does nothing.
@export var min_penetration := 0.05

## Size of the hole the moment a hand goes through, in meters.
@export var start_radius := 0.25

## How fast the dissolve spreads while the hand stays through, in m/s.
@export var spread_speed := 3.0

## How fast the scan rebuilds once the hand is out, in m/s.
@export var rebuild_speed := 8.0

## Furthest the dissolve spreads, in meters; 0 means the whole scan.
@export var max_radius := 0.0

var _material := ShaderMaterial.new()
var _meshes: Array[MeshInstance3D] = []
var _origins: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _radii: Array[float] = [0.0, 0.0]
# A hand only counts once it has been seen outside the scan, so starting
# inside geometry (spawn, a bad floor estimate) doesn't dissolve the world.
var _armed: Array[bool] = [false, false]
var _reach := 0.0


func _ready() -> void:
	_material.shader = DissolveShader
	# Only the scan's own meshes: nodes built at runtime under it, like a
	# WaterVolume's surface, have no owner and keep their own material.
	for mesh_instance: MeshInstance3D in scan.find_children("*", "MeshInstance3D", true, true):
		_meshes.append(mesh_instance)
		var aabb := mesh_instance.global_transform * mesh_instance.get_aabb()
		_reach = maxf(_reach, aabb.size.length())

	if _meshes:
		var original := _meshes[0].get_active_material(0) as BaseMaterial3D
		if original:
			_material.set_shader_parameter("albedo_texture", original.albedo_texture)
	if max_radius <= 0.0:
		max_radius = _reach


func _physics_process(delta: float) -> void:
	var hands: Array[XRController3D] = [left_hand, right_hand]
	for i in hands.size():
		var hit := {}
		if hands[i] and hands[i].get_is_active():
			hit = _penetration(hands[i])
			if hit.is_empty():
				_armed[i] = true
			elif not _armed[i]:
				hit = {}
		if hit.is_empty():
			_radii[i] = maxf(_radii[i] - rebuild_speed * delta, 0.0)
		elif _radii[i] <= 0.0:
			_origins[i] = hit.position
			_radii[i] = start_radius
		else:
			# Follow the hand's entry point loosely so the hole doesn't jitter.
			_origins[i] = _origins[i].lerp(hit.position, 1.0 - exp(-4.0 * delta))
			_radii[i] = minf(_radii[i] + spread_speed * delta, max_radius)

	var active := _radii[0] > 0.0 or _radii[1] > 0.0
	if active:
		_material.set_shader_parameter("sources", PackedVector4Array([
			Vector4(_origins[0].x, _origins[0].y, _origins[0].z, _radii[0]),
			Vector4(_origins[1].x, _origins[1].y, _origins[1].z, _radii[1]),
		]))
	# Only pay for the dissolve shader while something is dissolving.
	for mesh_instance in _meshes:
		mesh_instance.material_override = _material if active else null


## Where the head-to-hand line enters the scan, or empty if the hand isn't through.
func _penetration(hand: XRController3D) -> Dictionary:
	var from := camera.global_position
	var to := hand.global_position
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.position.distance_to(to) < min_penetration:
		return {}
	return hit
