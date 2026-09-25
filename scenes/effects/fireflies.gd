extends GPUParticles3D

## Fireflies that swarm around a hand while its grip is held, and scatter
## when it lets go.
##
## A hand that has gathered a swarm also carries a small light, so the
## fireflies light up the scan around it.

## Hands that can gather fireflies.
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
var _lights: Array[OmniLight3D] = [null, null]


func _ready() -> void:
	var hands := _hands()
	for i in hands.size():
		if not hands[i]:
			continue
		var light := OmniLight3D.new()
		light.name = "FireflyLight"
		light.light_color = light_color
		light.omni_range = light_range
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.visible = false
		hands[i].add_child(light)
		_lights[i] = light


func _process(delta: float) -> void:
	var hands := _hands()
	var hand_params := PackedVector4Array()
	var burst_params := PackedVector4Array()
	for i in hands.size():
		var hand := hands[i]
		var grip := 0.0
		if hand and hand.get_is_active():
			grip = hand.get_float(grip_action)

		if not _held[i] and grip >= grab_threshold:
			_held[i] = true
			_hold_times[i] = 0.0
		elif _held[i] and grip <= release_threshold:
			_held[i] = false
			if _hold_times[i] >= min_hold_time:
				_scatter(i)

		if _held[i]:
			_hold_times[i] += delta
		_pulls[i] = move_toward(_pulls[i], 1.0 if _held[i] else 0.0, pull_speed * delta)
		_bursts[i].w = move_toward(_bursts[i].w, 0.0, delta / burst_time)

		var at := hand.global_position if hand else Vector3.ZERO
		hand_params.append(Vector4(at.x, at.y, at.z, _pulls[i]))
		burst_params.append(_bursts[i])
		_update_light(i, delta)

	var params := process_material as ShaderMaterial
	params.set_shader_parameter("hands", hand_params)
	params.set_shader_parameter("bursts", burst_params)


func _scatter(i: int) -> void:
	var hand := _hands()[i]
	var at := hand.global_position
	_bursts[i] = Vector4(at.x, at.y, at.z, 1.0)
	hand.trigger_haptic_pulse(haptic_action, 0.0, haptic_amplitude, haptic_duration, 0.0)


func _update_light(i: int, delta: float) -> void:
	var light := _lights[i]
	if not light:
		return
	# Brightens as the swarm gathers, snaps off as it scatters.
	var target := 0.0
	if _held[i]:
		target = light_energy * minf(_hold_times[i] / light_build_time, 1.0)
	var rate := light_energy / light_build_time if _held[i] else light_energy / burst_time
	light.light_energy = move_toward(light.light_energy, target, rate * delta)
	light.visible = light.light_energy > 0.0


func _hands() -> Array[XRController3D]:
	return [left_hand, right_hand]
