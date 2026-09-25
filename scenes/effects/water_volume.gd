@tool
class_name WaterVolume
extends Node3D

## Box of water to drop anywhere: a surface you see into and through, and a
## trigger for what goes in.
##
## This node sits at the center of the water surface and the water fills
## [member size] below it, so place it at the waterline. Only turn it around
## the vertical axis: the surface is meant to face up. The waves are laid out
## in world space, so volumes side by side line up.
##
## The look comes from [member material] (see water_volume.gdshader). It is
## shared by every volume using it; make it unique to tweak one volume alone.

## Emitted when a body on [member detect_mask] enters the water.
signal body_entered(body: Node3D)
## Emitted when a body on [member detect_mask] leaves the water.
signal body_exited(body: Node3D)

const DEFAULT_MATERIAL := preload("res://scenes/effects/water_volume_material.tres")

## Width, depth and length of the water, in meters.
@export var size := Vector3(4.0, 1.0, 4.0):
	set(value):
		size = value.max(Vector3(0.01, 0.01, 0.01))
		_update()

## Surface grid resolution. The waves only move the surface where it has
## vertices, so use more for close-up water.
@export_range(0.0, 16.0, 0.5, "suffix:/m") var subdivisions_per_meter := 4.0:
	set(value):
		subdivisions_per_meter = value
		_update()

## Surface material; the default water when empty.
@export var material: ShaderMaterial:
	set(value):
		material = value
		_update()

## Physics layers of the bodies that trigger [signal body_entered]. The
## default is the XR Tools player body's layer.
@export_flags_3d_physics var detect_mask := 1 << 19:
	set(value):
		detect_mask = value
		_update()

var _surface: MeshInstance3D
var _area: Area3D
var _shape: BoxShape3D


func _ready() -> void:
	# Internal children are regenerated on load, never saved with the scene.
	_surface = MeshInstance3D.new()
	_surface.name = "Surface"
	_surface.mesh = PlaneMesh.new()
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Waves move the surface up and down past its mesh bounds.
	_surface.extra_cull_margin = 0.5
	add_child(_surface, false, INTERNAL_MODE_BACK)

	_shape = BoxShape3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	_area = Area3D.new()
	_area.name = "Volume"
	_area.collision_layer = 0
	_area.monitorable = false
	_area.add_child(collision)
	add_child(_area, false, INTERNAL_MODE_BACK)
	_area.body_entered.connect(body_entered.emit)
	_area.body_exited.connect(body_exited.emit)

	_update()


## Whether [param point], in global coordinates, is in the water.
func contains(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= size.x / 2.0 and absf(local.z) <= size.z / 2.0 \
			and local.y <= 0.0 and local.y >= -size.y


func _update() -> void:
	if not is_node_ready():
		return
	var plane := _surface.mesh as PlaneMesh
	plane.size = Vector2(size.x, size.z)
	plane.subdivide_width = maxi(ceili(size.x * subdivisions_per_meter) - 1, 0)
	plane.subdivide_depth = maxi(ceili(size.z * subdivisions_per_meter) - 1, 0)
	_surface.material_override = material if material else DEFAULT_MATERIAL

	_shape.size = size
	_area.position = Vector3(0.0, -size.y / 2.0, 0.0)
	_area.collision_mask = detect_mask
