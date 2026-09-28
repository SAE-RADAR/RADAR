@tool
class_name WaterVolume
extends Node3D

## Volume d'eau avec surface animée et interaction avec les mains XR.
##
## Lorsqu'une main entre dans l'eau, une petite vague circulaire
## apparaît à sa position, s'agrandit puis disparaît.

signal body_entered(body: Node3D)
signal body_exited(body: Node3D)

const DEFAULT_MATERIAL := preload("res://scenes/effects/water_volume_material.tres")

# Rayon extérieur du tore utilisé pour la vague (à l'échelle 1).
const WAVE_TORUS_INNER_RADIUS := 0.04
const WAVE_TORUS_OUTER_RADIUS := 0.06

# ---------------------------------------------------------
# CONFIGURATION DE L'EAU
# ---------------------------------------------------------

## Largeur, profondeur et hauteur du volume d'eau.
@export var size := Vector3(4.0, 1.0, 4.0):
	set(value):
		size = value.max(Vector3(0.01, 0.01, 0.01))
		_update()

## Résolution de la surface.
@export_range(0.0, 16.0, 0.5, "suffix:/m") var subdivisions_per_meter := 4.0:
	set(value):
		subdivisions_per_meter = value
		_update()

## Matériau de l'eau.
@export var material: ShaderMaterial:
	set(value):
		material = value
		_update()

## Couche de collision détectée par le volume.
@export_flags_3d_physics var detect_mask := 1 << 19:
	set(value):
		detect_mask = value
		_update()


# ---------------------------------------------------------
# CONFIGURATION DES VAGUES
# ---------------------------------------------------------

## Diamètre maximal de la vague (en mètres).
@export var wave_max_size := 0.35

## Durée de vie de la vague.
@export var wave_duration := 0.6

## Hauteur de la vague au-dessus de l'eau.
@export var wave_height := 0.015

## Opacité maximale de la vague.
@export_range(0.0, 1.0) var wave_opacity := 0.65


# ---------------------------------------------------------
# VARIABLES INTERNES
# ---------------------------------------------------------

var _surface: MeshInstance3D
var _area: Area3D
var _shape: BoxShape3D

# Mains actuellement dans l'eau (Node3D -> bool).
var _hands_in_water: Dictionary = {}


# ---------------------------------------------------------
# INITIALISATION
# ---------------------------------------------------------

func _ready() -> void:

	# Surface de l'eau
	_surface = MeshInstance3D.new()
	_surface.name = "Surface"
	_surface.mesh = PlaneMesh.new()
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Les vagues peuvent légèrement dépasser du maillage.
	_surface.extra_cull_margin = 0.5

	add_child(_surface, false, INTERNAL_MODE_BACK)

	# Volume de détection
	_shape = BoxShape3D.new()

	var collision := CollisionShape3D.new()
	collision.shape = _shape

	_area = Area3D.new()
	_area.name = "Volume"

	# Le volume ne possède pas sa propre couche.
	_area.collision_layer = 0
	_area.monitorable = false
	_area.add_child(collision)

	add_child(_area, false, INTERNAL_MODE_BACK)

	_area.body_entered.connect(body_entered.emit)
	_area.body_exited.connect(body_exited.emit)

	_update()


# ---------------------------------------------------------
# VERIFICATION DANS L'EAU
# ---------------------------------------------------------

## Renvoie true si un point global se trouve dans l'eau.
func contains(point: Vector3) -> bool:

	var local := to_local(point)

	return (
		absf(local.x) <= size.x / 2.0
		and absf(local.z) <= size.z / 2.0
		and local.y <= 0.0
		and local.y >= -size.y
	)


# ---------------------------------------------------------
# DETECTION DES MAINS
# ---------------------------------------------------------

func _process(_delta: float) -> void:

	# Ne rien faire dans l'éditeur.
	if Engine.is_editor_hint():
		return

	# Nettoyage des mains qui ont été supprimées.
	for key in _hands_in_water.keys():
		if not is_instance_valid(key):
			_hands_in_water.erase(key)

	for node in get_tree().get_nodes_in_group("water_hand"):

		var hand := node as Node3D
		if hand == null:
			continue

		var hand_position := hand.global_position
		var inside := contains(hand_position)
		var was_inside: bool = _hands_in_water.get(hand, false)

		if inside and not was_inside:
			# La main vient d'entrer dans l'eau.
			_hands_in_water[hand] = true
			_create_wave(hand_position)

		elif not inside and was_inside:
			# La main sort de l'eau.
			_hands_in_water[hand] = false


# ---------------------------------------------------------
# CREATION DE LA VAGUE
# ---------------------------------------------------------

func _create_wave(world_position: Vector3) -> void:

	var wave := MeshInstance3D.new()
	wave.name = "HandWave"
	wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Anneau 3D
	var torus := TorusMesh.new()
	torus.inner_radius = WAVE_TORUS_INNER_RADIUS
	torus.outer_radius = WAVE_TORUS_OUTER_RADIUS
	torus.rings = 32
	torus.ring_segments = 8
	wave.mesh = torus

	# Matériau de la vague
	var wave_material := StandardMaterial3D.new()
	wave_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wave_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wave_material.albedo_color = Color(0.65, 0.9, 1.0, wave_opacity)
	wave.material_override = wave_material

	# Position (en coordonnées locales, à la surface)
	add_child(wave)

	var local_position := to_local(world_position)
	local_position.y = wave_height
	wave.position = local_position

	# Échelle : le diamètre final vaut wave_max_size.
	# L'épaisseur (Y) reste constante pour éviter un anneau "gonflé".
	var start_scale := Vector3(0.1, 1.0, 0.1)
	var end_xz := wave_max_size / (WAVE_TORUS_OUTER_RADIUS * 2.0)
	var end_scale := Vector3(end_xz, 1.0, end_xz)

	wave.scale = start_scale

	# Animation
	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(wave, "scale", end_scale, wave_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.tween_property(wave_material, "albedo_color:a", 0.0, wave_duration)

	# Suppression de la vague à la fin.
	tween.chain().tween_callback(wave.queue_free)


# ---------------------------------------------------------
# MISE A JOUR DE L'EAU
# ---------------------------------------------------------

func _update() -> void:

	if not is_node_ready():
		return

	var plane := _surface.mesh as PlaneMesh

	plane.size = Vector2(size.x, size.z)
	plane.subdivide_width = maxi(ceili(size.x * subdivisions_per_meter) - 1, 0)
	plane.subdivide_depth = maxi(ceili(size.z * subdivisions_per_meter) - 1, 0)

	_surface.material_override = material if material else DEFAULT_MATERIAL

	# Collision du volume
	_shape.size = size
	_area.position = Vector3(0.0, -size.y / 2.0, 0.0)
	_area.collision_mask = detect_mask
