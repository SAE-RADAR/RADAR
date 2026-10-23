extends Node3D

@export var skip_to := ""
## With [member skip_to], runs that room in AR.
@export var skip_to_ar := false


func _ready() -> void:
	if skip_to:
		AppMode.mode = AppMode.Mode.AR if skip_to_ar else AppMode.Mode.VR
		Rooms.go_to.call_deferred(skip_to, false)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_go_to("thermes", AppMode.Mode.VR)
		KEY_2:
			_go_to("gros_pilier", AppMode.Mode.VR)
		KEY_3:
			_go_to("thermes", AppMode.Mode.AR)


func _go_to(room: String, mode: AppMode.Mode) -> void:
	AppMode.mode = mode
	Rooms.go_to(room)
