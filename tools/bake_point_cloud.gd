extends SceneTree

## Bakes a CloudCompare binary PLY point cloud (x, y, z float, red, green, blue
## uchar, scalar_Intensity float) into a points mesh ScanPointCloud can draw.
##
## Parsing millions of points in GDScript takes seconds, and a raw .ply isn't
## exported with the game, so this runs once, offline:
##
##   godot --headless --path . --script res://tools/bake_point_cloud.gd -- \
##       [source.ply] [output.mesh] [max_points]
##
## CloudCompare is Z-up: points are turned Y-up as (x, z, -y) and otherwise
## kept in the scan's own coordinates. Placing the cloud on the room's mesh is
## the ScanPointCloud node's transform.

const DEFAULT_SOURCE := "res://models/Nuage propre sans toît.ply"
const DEFAULT_OUTPUT := "res://assets/thermes/models/thermes_point_cloud.mesh"
## Quest 3 draws about this many points in stereo at a steady frame rate.
const DEFAULT_MAX_POINTS := 1500000

const RECORD_SIZE := 19 # 3 floats + 3 bytes + 1 float


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var source: String = args[0] if args.size() > 0 else DEFAULT_SOURCE
	var output: String = args[1] if args.size() > 1 else DEFAULT_OUTPUT
	var max_points: int = int(args[2]) if args.size() > 2 else DEFAULT_MAX_POINTS
	quit(0 if bake(source, output, max_points) else 1)


func bake(source: String, output: String, max_points: int) -> bool:
	var file := FileAccess.open(source, FileAccess.READ)
	if not file:
		push_error("Can't open %s: %s" % [source, error_string(FileAccess.get_open_error())])
		return false

	var vertex_count := 0
	var properties := PackedStringArray()
	var format := ""
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("format "):
			format = line
		elif line.begins_with("element vertex "):
			vertex_count = int(line.get_slice(" ", 2))
		elif line.begins_with("property "):
			properties.append(line)
		elif line == "end_header":
			break
	var expected := PackedStringArray([
		"property float x", "property float y", "property float z",
		"property uchar red", "property uchar green", "property uchar blue",
		"property float scalar_Intensity",
	])
	if format != "format binary_little_endian 1.0" or properties != expected:
		push_error("%s isn't a CloudCompare binary PLY with x y z red green blue scalar_Intensity" % source)
		return false

	var raw := file.get_buffer(vertex_count * RECORD_SIZE)
	if raw.size() < vertex_count * RECORD_SIZE:
		push_error("%s is truncated" % source)
		return false

	# Every step-th point: CloudCompare writes points in scan order, so a
	# stride thins the cloud evenly.
	var step := maxi(1, ceili(float(vertex_count) / max_points))
	var count := ceili(float(vertex_count) / step)
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	positions.resize(count)
	colors.resize(count)
	for i in count:
		var offset := i * step * RECORD_SIZE
		positions[i] = Vector3(
				raw.decode_float(offset),
				raw.decode_float(offset + 8),
				-raw.decode_float(offset + 4))
		colors[i] = Color8(raw[offset + 12], raw[offset + 13], raw[offset + 14])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)

	var error := ResourceSaver.save(mesh, output, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("Can't save %s: %s" % [output, error_string(error)])
		return false
	print("Baked %d of %d points into %s" % [count, vertex_count, output])
	return true
