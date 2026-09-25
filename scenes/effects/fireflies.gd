extends GPUParticles3D

## Fireflies that cling to a hand while its grip is held, and scatter when it
## lets go.
##
## The fireflies settle along the bones of the hand mesh's skeleton, so the
## swarm follows the hand's shape as it moves and closes into a fist. A hand
## that has gathered a swarm also carries a small light, so the fireflies
## light up the scan around it.

## Bone segments sent to the shader per hand; must match fireflies_process.gdshader.
const MAX_SEGMENTS := 32

## Hands that can gather fireflies. The first Skeleton3D under each (the hand
## mesh) gives the shape the fireflies cling to.
@export var left_hand: XRController3D
@export var right_hand: XRController3D

## Input action read as grip strength (0 to 1).
@export var grip_action := &"grip"

## Grip strength that starts a grab, and the lower one that ends it.
@export var grab_threshold := 0.6
@export var release_threshold := 0.35

## How quickly the pull ramps up and down, per second.
@export var pull_speed := 4.0

## Seconds the scatter lasts after letting go.
@export var burst_time := 0.25

## Minimum grab time before letting go scatters the swarm, so quick taps don't.
@export var min_hold_time := 0.4

## How quickly the tracked hand velocity follows the hand, per second. The hand
## mesh moves on physics ticks, so its per-frame motion is uneven.
@export var velocity_smoothing := 15.0

## Light carried by a hand holding a swarm.
@export var light_color := Color(0.5, 1.0, 0.4)
@export var light_energy := 0.8
@export var light_range := 1.5

## Seconds of holding before the swarm's light reaches full brightness.
@export var light_build_time := 2.0

## Haptic pulse when the swarm scatters.
@export var haptic_action := &"haptic"
@export var haptic_amplitude := 0.4
@export var haptic_duration := 0.12

var _held: Array[bool] = [false, false]
var _hold_times: Array[float] = [0.0, 0.0]
var _pulls: Array[float] = [0.0, 0.0]
var _bursts: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO]
var _burst_velocities: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _lights: Array[OmniLight3D] = [null, null]
var _skeletons: Array[Skeleton3D] = [null, null]
# Per hand, bone index pairs (parent, child) for each segment.
var _segments: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
var _centers: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _velocities: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _tracked: Array[bool] = [false, false]


func _ready() -> void:
	var hands := _hands()
	for i in hands.size():
		if not hands[i]:
			continue
		var skeletons := hands[i].find_children("*", "Skeleton3D", true, false)
		if skeletons:
			_skeletons[i] = skeletons[0]
			_segments[i] = _bone_segments(_skeletons[i])

		var light := OmniLight3D.new()
		light.name = "FireflyLight%d" % i
		light.light_color = light_color
		light.omni_range = light_range
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_lights[i] = light


func _process(delta: float) -> void:
	var grips: Array[float] = [0.0, 0.0]
	var hands := _hands()
	for i in hands.size():
		if hands[i] and hands[i].get_is_active():
			grips[i] = hands[i].get_float(grip_action)
	_update(delta, grips)


func _update(delta: float, grips: Array[float]) -> void:
	var hand_params := PackedVector4Array()
	var motion_params := PackedVector4Array()
	var starts := PackedVector3Array()
	var ends := PackedVector3Array()
	starts.resize(MAX_SEGMENTS * 2)
	ends.resize(MAX_SEGMENTS * 2)
	var burst_params := PackedVector4Array()
	var burst_velocity_params := PackedVector3Array()

	for i in 2:
		var count := _track_hand(i, delta, starts, ends)

		if not _held[i] and grips[i] >= grab_threshold:
			_held[i] = true
			_hold_times[i] = 0.0
		elif _held[i] and grips[i] <= release_threshold:
			_held[i] = false
			if _hold_times[i] >= min_hold_time:
				_scatter(i)

		if _held[i]:
			_hold_times[i] += delta
		_pulls[i] = move_toward(_pulls[i], 1.0 if _held[i] else 0.0, pull_speed * delta)
		_bursts[i].w = move_toward(_bursts[i].w, 0.0, delta / burst_time)

		var center := _centers[i]
		var velocity := _velocities[i]
		hand_params.append(Vector4(center.x, center.y, center.z, _pulls[i]))
		motion_params.append(Vector4(velocity.x, velocity.y, velocity.z, count))
		burst_params.append(_bursts[i])
		burst_velocity_params.append(_burst_velocities[i])
		_update_light(i, delta)

	var params := process_material as ShaderMaterial
	params.set_shader_parameter("hands", hand_params)
	params.set_shader_parameter("hand_motion", motion_params)
	params.set_shader_parameter("segment_starts", starts)
	params.set_shader_parameter("segment_ends", ends)
	params.set_shader_parameter("bursts", burst_params)
	params.set_shader_parameter("burst_velocities", burst_velocity_params)


## Updates the hand's center and velocity, and writes its bone segments into
## [param starts] and [param ends]. Returns the number of segments written.
func _track_hand(i: int, delta: float, starts: PackedVector3Array, ends: PackedVector3Array) -> int:
	var hand := _hands()[i]
	if not hand:
		return 0

	var center := hand.global_position
	var count := 0
	var skeleton := _skeletons[i]
	if skeleton and skeleton.is_visible_in_tree() and not _segments[i].is_empty():
		var pairs := _segments[i]
		@warning_ignore("integer_division")
		count = pairs.size() / 2
		var sum := Vector3.ZERO
		for s in count:
			var start := skeleton.global_transform * skeleton.get_bone_global_pose(pairs[s * 2]).origin
			var end := skeleton.global_transform * skeleton.get_bone_global_pose(pairs[s * 2 + 1]).origin
			starts[i * MAX_SEGMENTS + s] = start
			ends[i * MAX_SEGMENTS + s] = end
			sum += end
		center = sum / count

	if _tracked[i] and delta > 0.0:
		var raw := (center - _centers[i]) / delta
		_velocities[i] = _velocities[i].lerp(raw, 1.0 - exp(-velocity_smoothing * delta))
	_centers[i] = center
	_tracked[i] = true
	return count


func _scatter(i: int) -> void:
	var at := _centers[i]
	_bursts[i] = Vector4(at.x, at.y, at.z, 1.0)
	_burst_velocities[i] = _velocities[i]
	var hand := _hands()[i]
	if hand:
		hand.trigger_haptic_pulse(haptic_action, 0.0, haptic_amplitude, haptic_duration, 0.0)


func _update_light(i: int, delta: float) -> void:
	var light := _lights[i]
	if not light:
		return
	light.global_position = _centers[i]
	# Brightens as the swarm gathers, snaps off as it scatters.
	var target := 0.0
	if _held[i]:
		target = light_energy * minf(_hold_times[i] / light_build_time, 1.0)
	var rate := light_energy / light_build_time if _held[i] else light_energy / burst_time
	light.light_energy = move_toward(light.light_energy, target, rate * delta)
	light.visible = light.light_energy > 0.0


func _hands() -> Array[XRController3D]:
	return [left_hand, right_hand]


## Bone index pairs (parent, child) for every bone with a parent, up to
## [constant MAX_SEGMENTS].
static func _bone_segments(skeleton: Skeleton3D) -> PackedInt32Array:
	var pairs := PackedInt32Array()
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		if parent >= 0 and pairs.size() < MAX_SEGMENTS * 2:
			pairs.append(parent)
			pairs.append(bone)
	return pairs
