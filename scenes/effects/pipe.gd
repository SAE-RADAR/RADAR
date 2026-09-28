@tool
class_name Pipe
extends Path3D

## Glass pipe carrying water along its curve, hidden in the walls: it only
## shows through the holes HandDissolve burns in the scan.
##
## Draw the route with the curve; the water flows from its first point to its
## last. Sharp corners (points without handles) become elbows of
## [member bend_radius]. Inside the glass the water takes the color of its
## temperature, going from [member inlet_temperature] to
## [member outlet_temperature] along the pipe, and arrows of that color travel
## with it at [member flow_speed].
##
## Lay the pipe just behind the scan's surface, within HandDissolve's
## max_radius of where a hand goes through. It shows wherever a dissolve is
## burning (pipe_reveal.gdshaderinc) and the scan hides it everywhere else.
## It always shows in the editor.
##
## The look comes from pipe_water_material.tres (temperature colors, arrows)
## and pipe_glass_material.tres, shared by every pipe so the same color means
## the same temperature everywhere.

const WATER_MATERIAL := preload("res://scenes/effects/pipe_water_material.tres")
const GLASS_MATERIAL := preload("res://scenes/effects/pipe_glass_material.tres")

## Share of the glass's radius the water fills.
const WATER_RATIO := 0.7
## Corners turning less than this, in radians, stay as they are: the curve's
## own bends are already smooth.
const MIN_BEND_ANGLE := 0.15
## Most an elbow turns in one step, in radians.
const BEND_STEP := 0.2
## Distance the flow runs before its offset wraps, in meters; far enough that
## the jump in the currents is never seen.
const FLOW_WRAP := 1000.0

## Outer radius of the glass, in meters.
@export_range(0.005, 0.5, 0.005, "or_greater", "suffix:m") var radius := 0.05:
	set(value):
		radius = maxf(value, 0.005)
		_rebuild()

## Radius of the elbows the curve's sharp corners are rounded into, in
## meters; 0 keeps them sharp. Shrinks where segments are too short for it.
@export_range(0.0, 2.0, 0.01, "or_greater", "suffix:m") var bend_radius := 0.15:
	set(value):
		bend_radius = maxf(value, 0.0)
		_rebuild()

## Sides around the pipe.
@export_range(3, 32) var radial_segments := 12:
	set(value):
		radial_segments = maxi(value, 3)
		_rebuild()

## Temperature of the water entering at the curve's first point.
@export_range(-10.0, 100.0, 0.5, "or_greater", "or_less", "suffix:°C") var inlet_temperature := 40.0:
	set(value):
		inlet_temperature = value
		_update_parameters()

## Temperature of the water leaving at the curve's last point; lower than the
## inlet for hot water cooling on its way.
@export_range(-10.0, 100.0, 0.5, "or_greater", "or_less", "suffix:°C") var outlet_temperature := 38.0:
	set(value):
		outlet_temperature = value
		_update_parameters()

## Speed of the water from the first point to the last; still water, at 0,
## shows no arrows. Can change while running, like a valve being turned. To
## flow the other way, reverse the curve.
@export_range(0.0, 5.0, 0.05, "or_greater", "suffix:m/s") var flow_speed := 0.4:
	set(value):
		flow_speed = maxf(value, 0.0)
		_update_parameters()

## Shows the pipe everywhere, not only through dissolve holes, to debug it.
@export var always_visible := false:
	set(value):
		always_visible = value
		_update_parameters()

var _mesh_instance: MeshInstance3D
var _length := 0.0
var _flow_offset := 0.0


func _ready() -> void:
	# Internal children are regenerated on load, never saved with the scene.
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance, false, INTERNAL_MODE_BACK)
	curve_changed.connect(_rebuild)
	_rebuild()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	# Accumulated rather than TIME * speed in the shader, so the arrows don't
	# jump when the speed changes.
	_flow_offset = fmod(_flow_offset + flow_speed * delta, FLOW_WRAP)
	_mesh_instance.set_instance_shader_parameter(&"flow_offset", _flow_offset)


## Length of the pipe along its route, elbows included, in meters.
func get_pipe_length() -> float:
	return _length


func _rebuild() -> void:
	if not is_node_ready():
		return
	var route := _route()
	_length = 0.0
	for i in range(1, route.size()):
		_length += route[i].distance_to(route[i - 1])
	_mesh_instance.mesh = _build_mesh(route) if route.size() >= 2 else null
	_update_parameters()


func _update_parameters() -> void:
	if not is_node_ready():
		return
	_mesh_instance.set_instance_shader_parameter(&"pipe_length", _length)
	_mesh_instance.set_instance_shader_parameter(&"water_radius", radius * WATER_RATIO)
	_mesh_instance.set_instance_shader_parameter(&"inlet_temperature", inlet_temperature)
	_mesh_instance.set_instance_shader_parameter(&"outlet_temperature", outlet_temperature)
	_mesh_instance.set_instance_shader_parameter(&"flow_speed", flow_speed)
	_mesh_instance.set_instance_shader_parameter(&"always_visible", always_visible or Engine.is_editor_hint())


## The curve as a polyline, sharp corners rounded into elbows.
func _route() -> PackedVector3Array:
	var points := PackedVector3Array()
	if curve:
		for point in curve.tessellate():
			if points.is_empty() or points[-1].distance_to(point) > 0.0001:
				points.append(point)
	if points.size() < 3 or bend_radius <= 0.0:
		return points

	var route := PackedVector3Array([points[0]])
	for i in range(1, points.size() - 1):
		var corner := points[i]
		var before := points[i - 1]
		var after := points[i + 1]
		var angle := (corner - before).angle_to(after - corner)
		if angle < MIN_BEND_ANGLE:
			route.append(corner)
			continue
		# Leave half of each segment for the elbows at its other end.
		var cut := minf(bend_radius * tan(angle / 2.0),
				minf(corner.distance_to(before), corner.distance_to(after)) / 2.0)
		var start := corner + (before - corner).normalized() * cut
		var end := corner + (after - corner).normalized() * cut
		var steps := ceili(angle / BEND_STEP)
		for step in steps + 1:
			var t := float(step) / steps
			route.append(start.lerp(corner, t).lerp(corner.lerp(end, t), t))
	route.append(points[-1])
	return route


## Water tube (surface 0) inside the glass tube (surface 1), along [param route].
func _build_mesh(route: PackedVector3Array) -> ArrayMesh:
	var directions: Array[Vector3] = []
	for i in route.size() - 1:
		directions.append((route[i + 1] - route[i]).normalized())

	# One normal per segment, carried from each to the next so the tube
	# doesn't twist.
	var normals: Array[Vector3] = [_perpendicular(directions[0])]
	for k in range(1, directions.size()):
		var normal := normals[k - 1]
		if directions[k - 1].dot(directions[k]) > -0.999:
			normal = Quaternion(directions[k - 1], directions[k]) * normal
		normals.append((normal - directions[k] * normal.dot(directions[k])).normalized())

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			_tube_arrays(route, directions, normals, radius * WATER_RATIO))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			_tube_arrays(route, directions, normals, radius))
	mesh.surface_set_material(0, WATER_MATERIAL)
	mesh.surface_set_material(1, GLASS_MATERIAL)
	return mesh


## A ring of vertices at each point of [param route]. UV.x runs along the
## route in meters, UV.y once around.
func _tube_arrays(route: PackedVector3Array, directions: Array[Vector3],
		normals: Array[Vector3], tube_radius: float) -> Array:
	var vertices := PackedVector3Array()
	var vertex_normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var along := 0.0
	for i in route.size():
		if i > 0:
			along += route[i].distance_to(route[i - 1])
		var k := maxi(i - 1, 0)
		var direction := directions[k]
		var binormal := direction.cross(normals[k])
		# At a corner the ring lies in the plane halfway between both
		# segments, so the tube keeps its width through the joint.
		var miter := direction
		if i > 0 and i < directions.size():
			var halfway := directions[i - 1] + directions[i]
			if halfway.length_squared() > 0.0001:
				miter = halfway.normalized()
		var slant := maxf(direction.dot(miter), 0.05)
		for j in radial_segments + 1:
			var angle := TAU * j / radial_segments
			var outward := normals[k] * cos(angle) + binormal * sin(angle)
			var offset := outward * tube_radius
			vertices.append(route[i] + offset - direction * offset.dot(miter) / slant)
			vertex_normals.append(outward)
			uvs.append(Vector2(along, float(j) / radial_segments))

	# Clockwise seen from outside.
	var indices := PackedInt32Array()
	var ring := radial_segments + 1
	for i in route.size() - 1:
		for j in radial_segments:
			var a := i * ring + j
			var b := a + ring
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = vertex_normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


static func _perpendicular(direction: Vector3) -> Vector3:
	var reference := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	return reference.cross(direction).normalized()
