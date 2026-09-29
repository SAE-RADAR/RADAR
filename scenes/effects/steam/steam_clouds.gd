@tool
extends GPUParticles3D

@export var water: WaterVolume
@export var left_hand: XRController3D
@export var right_hand: XRController3D

@export var clouds_per_square_meter := 4.0
@export var hand_radius := 0.35
@export var hand_push := 3.0


func _ready() -> void:
	if not Engine.is_editor_hint() and not Interactions.steam:
		queue_free()
		return
	if not water:
		water = get_parent() as WaterVolume
	process_material = process_material.duplicate()
	_fit_to_water()
	if Engine.is_editor_hint():
		return
	for hand: XRController3D in [left_hand, right_hand]:
		if hand:
			hand.add_child(_hand_attractor())


func _fit_to_water() -> void:
	if not water:
		return
	var size := water.size
	amount = maxi(roundi(size.x * size.z * clouds_per_square_meter), 1)
	(process_material as ParticleProcessMaterial).emission_box_extents = Vector3(size.x * 0.45, 0.05, size.z * 0.45)
	visibility_aabb = AABB(Vector3(-size.x / 2.0 - 1.0, -0.5, -size.z / 2.0 - 1.0), Vector3(size.x + 2.0, 3.0, size.z + 2.0))


func _hand_attractor() -> GPUParticlesAttractorSphere3D:
	var attractor := GPUParticlesAttractorSphere3D.new()
	attractor.radius = hand_radius
	attractor.strength = -hand_push
	attractor.attenuation = 0.5
	return attractor
