extends Node3D

@export var skip_to := ""


func _ready() -> void:
	if not Interactions.room_choice:
		Rooms.go_to.call_deferred(Rooms.DEFAULT_ROOM, false)
	elif skip_to:
		Rooms.go_to.call_deferred(skip_to, false)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			Rooms.go_to("thermes")
		KEY_2:
			Rooms.go_to("gros_pilier")
