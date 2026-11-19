
extends Node3D

@export_file("*.ply")
var ply_path = "res://Models/Nuage propre sans toît.ply"

# Nombre maximum de points affichés
@export var max_points: int = 150000

# Taille des points
@export var point_radius: float = 0.03

func _ready():
	load_point_cloud()


func load_point_cloud():

	var file = FileAccess.open(ply_path, FileAccess.READ)

	if file == null:
		push_error("Impossible d'ouvrir le fichier PLY")
		return

	var vertex_count = 0
	var format = ""

	# Lecture de l'en-tête PLY
	while not file.eof_reached():
		var line = file.get_line()

		if line.begins_with("format "):
			format = line

		if line.begins_with("element vertex "):
			vertex_count = int(line.get_slice(" ", 2))

		if line == "end_header":
			break

	if format != "format binary_little_endian 1.0":
		push_error("Format PLY non compatible")
		file.close()
		return

	var data_start = file.get_position()
	var raw = file.get_buffer(file.get_length() - data_start)
	file.close()

	# Structure des données :
	# XYZ = 12 octets
	# RGB = 3 octets
	# Intensité = 4 octets
	var record_size = 19

	if raw.size() < vertex_count * record_size:
		push_error("Fichier PLY incomplet")
		return

	# Échantillonnage du nuage
	var step = maxi(
		1,
		int(ceil(float(vertex_count) / float(max_points)))
	)

	var count = int(ceil(float(vertex_count) / float(step)))

	print("Points originaux : ", vertex_count)
	print("Points affichés : ", count)

	# Calcul des limites spatiales
	var min_pos = Vector3(INF, INF, INF)
	var max_pos = Vector3(-INF, -INF, -INF)

	for i in range(count):

		var offset = i * step * record_size

		var pos = Vector3(
			raw.decode_float(offset),
			raw.decode_float(offset + 4),
			raw.decode_float(offset + 8)
		)

		min_pos = min_pos.min(pos)
		max_pos = max_pos.max(pos)

	# Centrage du nuage
	var center = (min_pos + max_pos) * 0.5

	# Création du matériau
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Création d'une petite sphère
	var sphere = SphereMesh.new()
	sphere.radius = point_radius
	sphere.height = point_radius * 2.0
	sphere.radial_segments = 6
	sphere.rings = 3
	sphere.material = material

	# Création du MultiMesh
	var multimesh = MultiMesh.new()

	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = sphere
	multimesh.instance_count = count

	# Remplissage des points
	for i in range(count):

		var offset = i * step * record_size

		var pos = Vector3(
			raw.decode_float(offset),
			raw.decode_float(offset + 4),
			raw.decode_float(offset + 8)
		)

		var r = float(raw[offset + 12]) / 255.0
		var g = float(raw[offset + 13]) / 255.0
		var b = float(raw[offset + 14]) / 255.0

		var point_color = Color(r, g, b, 1.0)

		var transform = Transform3D(
			Basis.IDENTITY,
			pos - center
		)

		multimesh.set_instance_transform(i, transform)
		multimesh.set_instance_color(i, point_color)

	# Ajout à la scène
	var cloud = MultiMeshInstance3D.new()
	cloud.multimesh = multimesh
	cloud.material_override = material

	add_child(cloud)

	print("Nuage de points chargé !")
