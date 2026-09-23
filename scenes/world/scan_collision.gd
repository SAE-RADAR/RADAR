extends Node3D

## Builds static trimesh collision for every mesh under this node at load,
## so the scan can be walked on and targeted by XR Tools teleport.

## Physics layers the generated collision lives on.
@export_flags_3d_physics var collision_layer := 1


func _ready() -> void:
	for mesh_instance: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if not mesh_instance.mesh:
			continue

		var shape := mesh_instance.mesh.create_trimesh_shape()
		# Scans are often single-sided or have flipped normals; collide from both sides.
		shape.backface_collision = true

		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = shape

		var body := StaticBody3D.new()
		body.name = "ScanCollision"
		body.collision_layer = collision_layer
		body.collision_mask = 0
		body.add_child(collision_shape)
		mesh_instance.add_child(body)
