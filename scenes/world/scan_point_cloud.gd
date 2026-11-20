@tool
class_name ScanPointCloud
extends Node3D

## Draws a baked point cloud (tools/bake_point_cloud.gd) in place of a scan's
## meshes.
##
## The scan's meshes stay in the scene, undrawn: their collision is still the
## floor to walk and teleport on and what [HandDissolve] raycasts against, and
## in AR they are still the invisible mask over passthrough. In AR
## ([member HandDissolve.mask_mode]) the cloud hides and the meshes draw again
## as that mask.
##
## In the editor both draw, to check that the cloud lines up with the meshes:
## this node's transform places the cloud on the scan.

const PointShader := preload("res://scenes/world/scan_point_cloud.gdshader")

## Points mesh from tools/bake_point_cloud.gd.
@export var mesh: Mesh:
	set(value):
		mesh = value
		_cloud.mesh = value
		# Breathing, dispersion and spiral move points around the cloud's
		# center; the baked points keep the scan's coordinates.
		_material.set_shader_parameter("cloud_center",
				value.get_aabb().get_center() if value else Vector3.ZERO)

## Node holding the scanned meshes the cloud replaces; its parent if empty.
@export var scan: Node3D

@export var hand_dissolve: HandDissolve

## Point diameter, in meters.
@export_range(0.001, 0.2, 0.001, "suffix:m") var point_size := 0.02:
	set(value):
		point_size = value
		_material.set_shader_parameter("point_size", value)

@export_group("Animation")
@export_range(0.0, 5.0, 0.1) var animation_speed := 1.0:
	set(value):
		animation_speed = value
		_material.set_shader_parameter("speed", value)
@export_range(0.0, 5.0, 0.1) var animation_strength := 1.0:
	set(value):
		animation_strength = value
		_material.set_shader_parameter("strength", value)

@export_subgroup("Effects")
## Whole cloud swells and shrinks around its center.
@export var breathing := false:
	set(value):
		breathing = value
		_material.set_shader_parameter("breathing", value)
## Vertical wave running along X.
@export var wave := false:
	set(value):
		wave = value
		_material.set_shader_parameter("wave", value)
## Each point drifts in and out from the center on its own phase.
@export var dispersion := false:
	set(value):
		dispersion = value
		_material.set_shader_parameter("dispersion", value)
## Points orbit around the vertical axis, farther ones wider.
@export var spiral := false:
	set(value):
		spiral = value
		_material.set_shader_parameter("spiral", value)
## A few points at a time jump sideways.
@export var glitch := false:
	set(value):
		glitch = value
		_material.set_shader_parameter("glitch", value)
## Points jitter and bands of them disappear, sweeping along X.
@export var erosion := false:
	set(value):
		erosion = value
		_material.set_shader_parameter("erosion", value)

var _cloud := MeshInstance3D.new()
var _material := ShaderMaterial.new()
var _scan_meshes: Array[MeshInstance3D] = []
var _showing_cloud := false


func _init() -> void:
	_material.shader = PointShader
	_material.set_shader_parameter("point_size", point_size)
	_cloud.material_override = _material
	_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Built at runtime with no owner: never saved, and skipped by the scan's
	# own scripts (ScanCollision, HandDissolve), which only take owned meshes.
	_cloud.name = "Cloud"


func _ready() -> void:
	add_child(_cloud)
	if Engine.is_editor_hint():
		return
	if not scan:
		scan = get_parent() as Node3D
	for mesh_instance: MeshInstance3D in scan.find_children("*", "MeshInstance3D", true, true):
		_scan_meshes.append(mesh_instance)
	_show_cloud(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var show_cloud := not (hand_dissolve and hand_dissolve.mask_mode)
	if show_cloud != _showing_cloud:
		_show_cloud(show_cloud)


func _show_cloud(show_cloud: bool) -> void:
	_showing_cloud = show_cloud
	_cloud.visible = show_cloud
	for mesh_instance in _scan_meshes:
		mesh_instance.visible = not show_cloud
