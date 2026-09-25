extends Node

const FadeScene := preload("res://addons/godot-xr-tools/effects/fade.tscn")

const SCENES := {
	"welcome": "res://scenes/navigation/room_choice/welcome_room.tscn",
	"thermes": "res://scenes/thermes.tscn",
	"gros_pilier": "res://scenes/world/Gros_Pilier.tscn",
}

const DEFAULT_ROOM := "thermes"
const FADE_DURATION := 0.3
const PLACEMENT_FRAMES := 4

var _changing := false
var _fade := 0.0


func go_to(room: String, fade_out := true) -> void:
	if _changing:
		return
	if not SCENES.has(room):
		push_error("Unknown room '%s', expected one of %s." % [room, SCENES.keys()])
		return
	_changing = true

	_add_fade(get_tree().current_scene)
	if fade_out:
		await _fade_to(1.0)
	else:
		_set_fade(1.0)

	get_tree().change_scene_to_file(SCENES[room])
	await get_tree().scene_changed
	_add_fade(get_tree().current_scene)
	for i in PLACEMENT_FRAMES:
		await get_tree().physics_frame

	await _fade_to(0.0)
	_changing = false


func _add_fade(scene: Node) -> void:
	for camera: XRCamera3D in scene.find_children("*", "XRCamera3D", true, false):
		if camera.find_children("*", "XRToolsFade", false, false).is_empty():
			camera.add_child(FadeScene.instantiate())
	_set_fade(_fade)


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_method(_set_fade, _fade, alpha, FADE_DURATION)
	await tween.finished


func _set_fade(alpha: float) -> void:
	_fade = alpha
	XRToolsFade.set_fade(self, Color(0, 0, 0, alpha))
