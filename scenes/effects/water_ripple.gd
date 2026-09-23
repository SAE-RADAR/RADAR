extends MeshInstance3D

## One-shot water ripple: advances the shader's age and frees itself when done.

## Seconds before the ripple has fully faded and is removed.
@export var lifetime := 4.0

var _age := 0.0


func _ready() -> void:
	set_instance_shader_parameter("lifetime", lifetime)
	set_instance_shader_parameter("age", 0.0)


func _process(delta: float) -> void:
	_age += delta
	set_instance_shader_parameter("age", _age)
	if _age >= lifetime:
		queue_free()
