@tool
class_name Cascade
extends Node3D

## Waterfall to drop anywhere: a sheet of water pouring over a ledge, tearing
## into streaks as it falls, with spray, mist and foam where it lands.
##
## This node sits at the middle of the lip the water pours over. The water
## leaves it forward (toward -Z) at [member flow_speed], then falls
## [member height] meters; [method landing_point] tells where it lands, to put
## a [WaterVolume] or a basin there. Only turn it around the vertical axis: the
## water always falls straight down.
##
## The sheet is a ribbon mesh following the water's path (cascade_sheet.gdshader,
## looks in cascade_sheet_material.tres). The other layers are GPUParticles3D
## driven by cascade_process.gdshader, drawn as streaks
## (cascade_streak.gdshader), puffs (cascade_mist.gdshader) or floating foam
## (cascade_foam.gdshader). Everything is lit by the scene.

const GRAVITY := 9.8
const SHEET_MATERIAL := preload("res://scenes/effects/cascade_sheet_material.tres")
const PROCESS_SHADER := preload("res://scenes/effects/cascade_process.gdshader")
const STREAK_SHADER := preload("res://scenes/effects/cascade_streak.gdshader")
const MIST_SHADER := preload("res://scenes/effects/cascade_mist.gdshader")
const FOAM_SHADER := preload("res://scenes/effects/cascade_foam.gdshader")

## Width of the lip the water pours over, in meters.
@export_range(0.05, 20.0, 0.05, "or_greater", "suffix:m") var width := 1.5:
	set(value):
		width = maxf(value, 0.05)
		_update()

## Drop from the lip to where the water lands, in meters.
@export_range(0.1, 50.0, 0.05, "or_greater", "suffix:m") var height := 3.0:
	set(value):
		height = maxf(value, 0.1)
		_update()

## Speed the water leaves the lip at; faster water lands further out.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:m/s") var flow_speed := 1.5:
	set(value):
		flow_speed = maxf(value, 0.0)
		_update()

## Streaks torn from each meter of the sheet per second.
@export_range(0.0, 1000.0, 1.0, "or_greater", "suffix:/s/m") var density := 160.0:
	set(value):
		density = maxf(value, 0.0)
		_update()

## Tint and opacity of the clear water leaving the lip.
@export var water_color := Color(0.6, 0.78, 0.8, 0.35):
	set(value):
		water_color = value
		_update()

## Tint and opacity of the white water it turns into as it takes in air, and
## of the spray, mist and foam.
@export var foam_color := Color(0.93, 0.96, 1.0, 0.85):
	set(value):
		foam_color = value
		_update()

## How much spray splashes up where the water lands; none at 0.
@export_range(0.0, 3.0, 0.05) var spray := 1.0:
	set(value):
		spray = value
		_update()

## How much mist rises where the water lands; none at 0.
@export_range(0.0, 3.0, 0.05) var mist := 1.0:
	set(value):
		mist = value
		_update()

## How much foam spreads where the water lands; none at 0, for water landing
## on rock rather than in a pool.
@export_range(0.0, 3.0, 0.05) var foam := 1.0:
	set(value):
		foam = value
		_update()

## Looping sound played where the water lands; silent when empty. Only plays
## in game, not in the editor.
@export var sound: AudioStream:
	set(value):
		sound = value
		_update()

@export_range(-40.0, 20.0, 0.5, "suffix:dB") var sound_volume_db := 0.0:
	set(value):
		sound_volume_db = value
		_update()

## Whether the water flows. Stopping lets the water already out finish falling.
@export var emitting := true:
	set(value):
		emitting = value
		_update()

var _sheet: MeshInstance3D
var _streaks: GPUParticles3D
var _spray: GPUParticles3D
var _mist: GPUParticles3D
var _foam: GPUParticles3D
var _sound: AudioStreamPlayer3D


func _ready() -> void:
	# Internal children are regenerated on load, never saved with the scene.
	_sheet = MeshInstance3D.new()
	_sheet.name = "Sheet"
	_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sheet.material_override = SHEET_MATERIAL
	# The sheet sways past its mesh bounds.
	_sheet.extra_cull_margin = 0.5
	add_child(_sheet, false, INTERNAL_MODE_BACK)

	_streaks = _add_layer("Streaks", STREAK_SHADER)
	_spray = _add_layer("Spray", STREAK_SHADER)
	_mist = _add_layer("Mist", MIST_SHADER)
	_foam = _add_layer("Foam", FOAM_SHADER)

	_sound = AudioStreamPlayer3D.new()
	_sound.name = "Sound"
	add_child(_sound, false, INTERNAL_MODE_BACK)

	_update()


## Middle of where the water lands, in global coordinates.
func landing_point() -> Vector3:
	return to_global(_landing())


func _landing() -> Vector3:
	return _path_point(_fall_time())


func _fall_time() -> float:
	return sqrt(2.0 * height / GRAVITY)


## Where the water is [param time] seconds after leaving the lip.
func _path_point(time: float) -> Vector3:
	return Vector3(0.0, -0.5 * GRAVITY * time * time, -flow_speed * time)


func _add_layer(layer_name: String, draw_shader: Shader) -> GPUParticles3D:
	var process := ShaderMaterial.new()
	process.shader = PROCESS_SHADER
	var draw := ShaderMaterial.new()
	draw.shader = draw_shader
	# Drawn after water surfaces, whose refraction comes from a copy of the
	# screen taken before any transparent pass and would paint over them.
	draw.render_priority = 1
	var quad := QuadMesh.new()
	quad.material = draw

	var particles := GPUParticles3D.new()
	particles.name = layer_name
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.fixed_fps = 0
	particles.interpolate = false
	particles.process_material = process
	particles.draw_pass_1 = quad
	add_child(particles, false, INTERNAL_MODE_BACK)
	return particles


func _update() -> void:
	if not is_node_ready():
		return
	var fall_time := _fall_time()
	var landing := _landing()
	var impact_speed := Vector2(flow_speed, GRAVITY * fall_time).length()
	var half_width := width / 2.0

	_sheet.mesh = _build_sheet_mesh(fall_time)
	_sheet.visible = emitting
	_sheet.set_instance_shader_parameter("sheet_width", width)
	_sheet.set_instance_shader_parameter("fall_time", fall_time)
	_sheet.set_instance_shader_parameter("water_color", water_color)
	_sheet.set_instance_shader_parameter("foam_color", foam_color)

	# Streaks the sheet tears into, showing where it starts to tear and gone
	# once they reach the landing height.
	_set_layer(_streaks, fall_time + 0.1, density * width, {
		# Inside the sheet's frayed edges.
		emission_extents = Vector3(half_width * 0.85, 0.02, 0.05),
		emission_direction = Vector3.FORWARD,
		spread = 0.04,
		initial_velocity = flow_speed,
		velocity_random = 0.15,
		velocity_mask = Vector3.ONE,
		grav = Vector3(0.0, -GRAVITY, 0.0),
		vel_damping = 0.0,
		turbulence = 1.5,
		kill_depth = height,
		color = Color(foam_color.lerp(water_color, 0.4), foam_color.a * 0.6),
		color_end = foam_color,
		scale_initial = 0.07,
		scale_add = 0.08,
		scale_random = 0.4,
		stretch = 0.045,
		fade_in = 0.35,
		fade_out = 0.0,
	})
	_streaks.visibility_aabb = AABB(
			Vector3(-half_width - 0.5, -height - 0.5, landing.z - 1.0),
			Vector3(width + 1.0, height + 1.0, -landing.z + 1.5))

	# Droplets thrown up and out where the water lands, like the blood spray
	# this is adapted from.
	_spray.position = landing
	_set_layer(_spray, 0.8, spray * 80.0 * width, {
		emission_extents = Vector3(half_width, 0.02, 0.15),
		emission_direction = Vector3(0.0, 1.0, -0.4),
		spread = 0.7,
		initial_velocity = impact_speed * 0.3,
		velocity_random = 0.6,
		velocity_mask = Vector3.ONE,
		grav = Vector3(0.0, -GRAVITY, 0.0),
		vel_damping = 1.0,
		turbulence = 0.0,
		kill_depth = 0.05,
		color = foam_color,
		color_end = foam_color,
		scale_initial = 0.03,
		scale_add = -0.01,
		scale_random = 0.5,
		stretch = 0.03,
		fade_in = 0.02,
		fade_out = 0.4,
	})

	# Mist puffing up and drifting off the impact.
	var mist_color := Color(foam_color.lerp(Color.WHITE, 0.5), 0.2)
	_mist.position = landing + Vector3(0.0, 0.1, 0.0)
	_set_layer(_mist, 3.0, mist * 12.0 * width, {
		emission_extents = Vector3(half_width, 0.05, 0.25),
		emission_direction = Vector3(0.0, 1.0, -0.3),
		spread = 1.0,
		initial_velocity = impact_speed * 0.15,
		velocity_random = 0.5,
		velocity_mask = Vector3.ONE,
		grav = Vector3(0.0, 0.15, 0.0),
		vel_damping = 1.2,
		turbulence = 0.3,
		kill_depth = -1.0,
		color = mist_color,
		color_end = mist_color,
		scale_initial = 0.4,
		scale_add = 1.2,
		scale_random = 0.4,
		stretch = 0.0,
		fade_in = 0.15,
		fade_out = 0.6,
	})

	# Foam spreading out on the water, thinning as it goes. Floats clear of
	# the wave crests of a WaterVolume.
	_foam.position = landing + Vector3(0.0, 0.04, 0.0)
	_set_layer(_foam, 5.0, foam * 6.0 * width, {
		emission_extents = Vector3(half_width * 0.8, 0.0, 0.2),
		emission_direction = Vector3.FORWARD,
		spread = PI,
		initial_velocity = 0.3 + impact_speed * 0.05,
		velocity_random = 0.7,
		velocity_mask = Vector3(1.0, 0.0, 1.0),
		grav = Vector3.ZERO,
		vel_damping = 0.4,
		turbulence = 0.0,
		kill_depth = -1.0,
		color = foam_color,
		color_end = foam_color,
		scale_initial = 0.3,
		scale_add = 0.6,
		scale_random = 0.4,
		stretch = 0.0,
		fade_in = 0.1,
		fade_out = 0.5,
	})

	var base_aabb := AABB(Vector3(-half_width - 2.5, -0.5, -3.0), Vector3(width + 5.0, 3.5, 6.0))
	_spray.visibility_aabb = base_aabb
	_mist.visibility_aabb = base_aabb
	_foam.visibility_aabb = base_aabb

	_sound.position = landing
	_sound.volume_db = sound_volume_db
	if _sound.stream != sound:
		_sound.stream = sound
	var should_play := sound != null and emitting and not Engine.is_editor_hint()
	if should_play and not _sound.playing:
		_sound.play()
	elif not should_play and _sound.playing:
		_sound.stop()


## Sizes [param particles] for [param rate] particles per second living
## [param lifetime] seconds, and sets its process shader [param params].
func _set_layer(particles: GPUParticles3D, lifetime: float, rate: float, params: Dictionary) -> void:
	particles.visible = rate > 0.0
	particles.emitting = emitting and rate > 0.0
	particles.lifetime = lifetime
	# Already flowing when the scene loads.
	particles.preprocess = lifetime
	particles.amount = maxi(ceili(rate * lifetime), 1)
	var material := particles.process_material as ShaderMaterial
	for param in params:
		material.set_shader_parameter(param, params[param])


## Ribbon along the water's path, in equal steps of time down the fall, facing
## away from the lip.
func _build_sheet_mesh(fall_time: float) -> ArrayMesh:
	var rows := clampi(ceili(height * 6.0), 8, 64)
	var columns := clampi(ceili(width * 4.0), 2, 48)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	for row in rows + 1:
		var fall := float(row) / rows
		var time := fall * fall_time
		var point := _path_point(time)
		# Perpendicular to the path: up at the lip, forward once falling.
		var normal := Vector3(0.0, flow_speed, -GRAVITY * time)
		normal = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.FORWARD
		for column in columns + 1:
			var across := float(column) / columns
			vertices.append(point + Vector3((across - 0.5) * width, 0.0, 0.0))
			normals.append(normal)
			tangents.append_array([1.0, 0.0, 0.0, 1.0])
			uvs.append(Vector2(across, fall))

	# Clockwise seen from the side the normals face.
	var indices := PackedInt32Array()
	for row in rows:
		for column in columns:
			var i := row * (columns + 1) + column
			var below := i + columns + 1
			indices.append_array([i, below, i + 1, i + 1, below, below + 1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
