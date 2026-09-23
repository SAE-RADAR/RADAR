extends MeshInstance3D

## Spin rate around the Y axis, in degrees per second.
@export var degrees_per_second := 45.0


func _process(delta: float) -> void:
	rotate_y(deg_to_rad(degrees_per_second * delta))
