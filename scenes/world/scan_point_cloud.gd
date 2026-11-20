extends Node3D

@export_group("Nuage de points")
@export_file("*.ply") var ply_path: String = "res://Models/Nuage propre sans toît.ply"
@export_range(1000, 500000, 1000) var max_points: int = 150000
@export_range(0.001, 0.2, 0.001) var point_radius: float = 0.03

@export_group("Animation")
@export_range(0.0, 5.0, 0.1) var animation_speed: float = 1.0
@export_range(0.0, 5.0, 0.1) var animation_strength: float = 1.0

@export_group("Effets - activation")
@export var breathing: bool = false
@export var wave: bool = false
@export var dispersion: bool = false
@export var spiral: bool = false
@export var glitch: bool = false
@export var erosion: bool = false

var cloud: MultiMeshInstance3D
var shader_material: ShaderMaterial


func _ready():
	load_point_cloud()


func _process(_delta):
	if shader_material:
		shader_material.set_shader_parameter("breathing", breathing)
		shader_material.set_shader_parameter("wave", wave)
		shader_material.set_shader_parameter("dispersion", dispersion)
		shader_material.set_shader_parameter("spiral", spiral)
		shader_material.set_shader_parameter("glitch", glitch)
		shader_material.set_shader_parameter("erosion", erosion)
		shader_material.set_shader_parameter("speed", animation_speed)
		shader_material.set_shader_parameter("strength", animation_strength)


func load_point_cloud():
	var file = FileAccess.open(ply_path, FileAccess.READ)
	if file == null:
		push_error("Impossible d'ouvrir le fichier PLY")
		return

	var header = ""
	while not file.eof_reached():
		var line = file.get_line()
		header += line + "\n"
		if line.strip_edges() == "end_header":
			break

	var vertex_count = 0
	for line in header.split("\n"):
		if line.begins_with("element vertex"):
			vertex_count = int(line.split(" ")[2])

	if vertex_count <= 0:
		push_error("Nombre de points introuvable")
		return

	var data = file.get_buffer(file.get_length() - file.get_position())
	file.close()

	var stride = 19
	var total_points = min(vertex_count, max_points)
	var step = max(1, int(vertex_count / total_points))

	var positions = PackedVector3Array()
	var colors = PackedColorArray()

	var min_pos = Vector3(INF, INF, INF)
	var max_pos = Vector3(-INF, -INF, -INF)

	for i in range(0, vertex_count, step):
		if positions.size() >= max_points:
			break

		var offset = i * stride
		if offset + stride > data.size():
			break

		var x = data.decode_float(offset)
		var y = data.decode_float(offset + 4)
		var z = data.decode_float(offset + 8)

		var r = data[offset + 12]
		var g = data[offset + 13]
		var b = data[offset + 14]

		var pos = Vector3(x, y, z)
		positions.append(pos)

		colors.append(Color(
			float(r) / 255.0,
			float(g) / 255.0,
			float(b) / 255.0,
			1.0
		))

		min_pos = min_pos.min(pos)
		max_pos = max_pos.max(pos)

	var center = (min_pos + max_pos) / 2.0

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = SphereMesh.new()

	var sphere = mm.mesh as SphereMesh
	sphere.radius = point_radius
	sphere.height = point_radius * 2.0

	mm.instance_count = positions.size()

	for i in range(positions.size()):
		var pos = positions[i] - center
		mm.set_instance_transform(i, Transform3D(Basis(), pos))
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, Color(randf(), randf(), randf(), 1.0))

	cloud = MultiMeshInstance3D.new()
	cloud.multimesh = mm
	add_child(cloud)

	shader_material = ShaderMaterial.new()
	shader_material.shader = create_shader()
	cloud.material_override = shader_material


func create_shader() -> Shader:
	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded;

uniform bool breathing = false;
uniform bool wave = false;
uniform bool dispersion = false;
uniform bool spiral = false;
uniform bool glitch = false;
uniform bool erosion = false;

uniform float speed = 1.0;
uniform float strength = 1.0;

varying vec3 original_pos;
varying float seed_value;

void vertex() {
	vec3 p = INSTANCE_TRANSFORM[3].xyz;
	original_pos = p;
	seed_value = INSTANCE_CUSTOM.r;

	float t = TIME * speed;
	float d = length(p);

	// Respiration
	if (breathing) {
		float pulse = sin(t * 1.5) * 0.5 + 0.5;
		p += normalize(p + vec3(0.001)) * pulse * strength * 0.3;
	}

	// Onde
	if (wave) {
		float w = sin(p.x * 0.5 + t * 2.0);
		p.y += w * strength * 0.5;
	}

	// Dispersion
	if (dispersion) {
		float amount = sin(t + seed_value * 10.0);
		p += normalize(p + vec3(0.001)) * amount * strength * 0.5;
	}

	// Spirale
	if (spiral) {
		float angle = t * 0.5 + seed_value * 6.283;
		float radius = length(p.xz);
		p.x += sin(angle) * radius * 0.1 * strength;
		p.z += cos(angle) * radius * 0.1 * strength;
	}

	// Glitch
	if (glitch) {
		float g = step(0.96, fract(sin(seed_value * 123.4 + floor(t * 10.0)) * 43758.5));
		p.x += g * sin(t * 30.0) * strength;
		p.z += g * cos(t * 25.0) * strength;
	}

	// Érosion
	if (erosion) {
		float e = sin(t * 2.0 + seed_value * 50.0);
		p += normalize(p + vec3(0.001)) * e * strength * 0.2;
	}

	VERTEX = p;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = 1.0;

	// Érosion visuelle
	if (erosion) {
		float mask = sin(original_pos.x * 10.0 + TIME * speed);
		if (mask > 0.8) {
			discard;
		}
	}
}
"""
	return shader
