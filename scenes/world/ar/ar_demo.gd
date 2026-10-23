extends Control

## Desktop demo of the AR mode, without a headset: the thermes run in AR
## ([ARSession]) over a simulated passthrough, and a simulated QR code tracker
## stands in for the headset's.
##
## The "real" site is the scan itself, drawn normally in a world of its own
## (Reality), where it stands at [member real_site], as the real thermes stand
## somewhere in the headset's tracking space. A printed code is stuck on it
## where the room's [QRMarker] is (off by [member code_error] while G is on).
## While that code is in view, near enough and facing the camera, an
## [OpenXRMarkerTracker] reports its pose as the headset would, and ARSession
## lines the room up with it. The AR layer (pipes, water, the scan as a mask)
## is drawn over the simulated passthrough.
##
## WASD (ZQSD on AZERTY): walk; drag with the left mouse button: look; Q/E
## (A/E): down/up; Shift: faster. 1 to 3: go to the code, a basin, a pipe.
## Right mouse button: dig a hole in the wall under the cursor. Tab: what is
## shown. C: calibrate (arrows: move the scan,
## Page Up/Down: raise/lower, Home/End: turn, Backspace: reset). G: misplace
## the printed code. H: hide the help. R: restart.

const ROOM := preload("res://scenes/thermes.tscn")
const DemoHand := preload("res://scenes/effects/pipe_demo_hand.gd")
const TRACKER_NAME := &"ar_demo_qr"
const VIEWS: Array[String] = [
	"passthrough simulé + calque AR",
	"passthrough simulé seul",
	"calque AR seul (damier = transparent, le passthrough s'y voit)",
]
## Places the number keys go to: what is looked at, in the room, and where
## from, relative to it (for the code, in front of it).
const STATIONS: Array[Dictionary] = [
	{"name": "QR code", "node": "QRMarker", "from": Vector3(0.0, 0.2, 2.0)},
	{"name": "bassin", "node": "Thermes vestiges/WaterVolume2", "from": Vector3(0.0, 1.6, 4.0)},
	{"name": "tuyau (clic droit sur le mur)", "node": "Thermes vestiges/Pipe", "from": Vector3(0.3, 0.4, 1.8)},
]
## Modules across the drawn QR code, quiet zone included.
const CODE_MODULES := 25
const CODE_QUIET_ZONE := 2

## Where the real thermes stand in the headset's tracking space: anywhere but
## where the scan is, as nothing ties the two together until a code is seen.
@export var real_site := Transform3D(Basis(Vector3.UP, deg_to_rad(35.0)), Vector3(6.0, -1.0, 4.0))

## How far the printed code is from where its QRMarker says while G is on, as
## when it is stuck a bit off on the real wall: calibration corrects it.
@export var code_error := Transform3D(Basis(Vector3.UP, deg_to_rad(4.0)), Vector3(0.15, 0.05, 0.0))

## The simulated headset sees the code within this distance, in meters, when
## it faces the camera. ARSession only follows it within its own
## max_marker_distance.
@export var detection_distance := 6.0

## Noise on the simulated code pose, in meters, as real tracking has.
@export var pose_jitter := 0.004

## Distance from the code the camera starts at, in meters: too far for
## ARSession to follow it.
@export var start_distance := 4.5

@export var walk_speed := 1.4
@export var run_speed := 4.0
## Degrees turned per pixel dragged.
@export var look_sensitivity := 0.2

@onready var _reality: SubViewportContainer = %Reality
@onready var _reality_camera: Camera3D = %RealityCamera
@onready var _real_scan: Node3D = %RealScan
@onready var _code: MeshInstance3D = %Code
@onready var _checker: Control = %Checker
@onready var _ar: SubViewportContainer = %AR
@onready var _ar_viewport: SubViewport = %ARViewport
@onready var _help: Label = %Help

var _room: Node3D
var _session: ARSession
var _camera: XRCamera3D
var _marker: QRMarker
var _tracker := OpenXRMarkerTracker.new()
var _code_seen_at := -1.0
var _misplaced := false
var _view := 0
# The head, in tracking space.
var _head := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	AppMode.mode = AppMode.Mode.AR
	_room = ROOM.instantiate()
	_session = _room.get_node("ARSession")
	_session.align_without_xr = false
	_ar_viewport.add_child(_room)
	_camera = _session.camera
	for node in _room.find_children("*", "Marker3D", true, false):
		if node is QRMarker:
			_marker = node
			break

	# A mouse-driven hand, so HandDissolve digs where the cursor is.
	var hand := DemoHand.new()
	hand.name = "DemoHand"
	hand.camera = _camera
	_room.add_child(hand)
	_session.hand_dissolve.left_hand = hand

	_tracker.name = TRACKER_NAME
	_tracker.marker_type = OpenXRSpatialComponentMarkerList.MARKER_TYPE_QRCODE
	_tracker.set_marker_data(_marker.data)
	_tracker.spatial_tracking_state = OpenXRSpatialEntityTracker.ENTITY_TRACKING_STATE_PAUSED
	XRServer.add_tracker(_tracker)

	_real_scan.transform = real_site
	_code.mesh = _code_mesh()
	_place_code()

	# Start facing the code, a few steps back from it.
	_go_to_station(0, Vector3(0.0, 0.2, start_distance))
	_update_view()


func _exit_tree() -> void:
	XRServer.remove_tracker(_tracker)


func _process(delta: float) -> void:
	_walk(delta)
	var head := Transform3D(Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0)), _head)
	_reality_camera.global_transform = head
	# Like the headset's head pose, in the origin's (tracking) space.
	_camera.transform = head
	_track_code(head)
	if _session.is_calibrating():
		_session.calibrate(
				Vector2(_axis(KEY_LEFT, KEY_RIGHT), _axis(KEY_DOWN, KEY_UP)),
				Vector2(_axis(KEY_HOME, KEY_END), _axis(KEY_PAGEDOWN, KEY_PAGEUP)), delta)
	_update_help()


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= motion.relative.x * look_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * look_sensitivity, -85.0, 85.0)
		return

	var key := event as InputEventKey
	if not key or not key.pressed or key.echo:
		return
	var station := key.physical_keycode - KEY_1
	if station >= 0 and station < STATIONS.size():
		_go_to_station(station)
		get_viewport().set_input_as_handled()
		return
	match key.physical_keycode:
		KEY_TAB:
			_view = (_view + 1) % VIEWS.size()
			_update_view()
		KEY_C:
			if _session.is_aligned():
				_session.set_calibrating(not _session.is_calibrating())
		KEY_BACKSPACE:
			_session.reset_calibration()
		KEY_G:
			_misplaced = not _misplaced
			_place_code()
		KEY_H:
			_help.visible = not _help.visible
		KEY_R:
			get_tree().reload_current_scene()
		_:
			return
	get_viewport().set_input_as_handled()


## Puts the head at a station of [constant STATIONS], looking at it, from
## [param from] instead of the station's own when given.
func _go_to_station(index: int, from := Vector3.INF) -> void:
	var station := STATIONS[index]
	var node: Node3D = _room.get_node(station.node)
	var target := node.global_position
	var path := node as Path3D
	if path:
		target = path.global_transform * path.curve.sample_baked(path.curve.get_baked_length() * 0.5)
	var offset: Vector3 = station.from if from == Vector3.INF else from
	if node is QRMarker:
		offset = node.global_basis * offset
	# Where the site really is: the room lines up with it once the code is seen.
	var eye := real_site * (target + offset)
	var to_target := real_site * target - eye
	_head = eye
	_yaw = rad_to_deg(atan2(-to_target.x, -to_target.z))
	_pitch = rad_to_deg(asin(to_target.normalized().y))


func _walk(delta: float) -> void:
	var input := Vector3(_axis(KEY_A, KEY_D), _axis(KEY_Q, KEY_E), _axis(KEY_W, KEY_S))
	var speed := run_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
	_head += Basis(Vector3.UP, deg_to_rad(_yaw)) * input * speed * delta


## -1, 0 or 1 from two keys, by their place on the keyboard (WASD is ZQSD on
## AZERTY).
func _axis(negative: Key, positive: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))


## Reports the printed code to ARSession while the simulated headset sees it.
func _track_code(head: Transform3D) -> void:
	var code := _code_transform()
	var to_head := head.origin - code.origin
	var seen := to_head.length() < detection_distance \
			and code.basis.z.dot(to_head.normalized()) > 0.3 \
			and _reality_camera.is_position_in_frustum(code.origin)
	_code_seen_at = to_head.length() if seen else -1.0
	if not seen:
		_tracker.spatial_tracking_state = OpenXRSpatialEntityTracker.ENTITY_TRACKING_STATE_PAUSED
		return
	var jitter := Vector3(randfn(0.0, 1.0), randfn(0.0, 1.0), randfn(0.0, 1.0)) * pose_jitter
	var tilt := Basis.from_euler(Vector3(randfn(0.0, 1.0), randfn(0.0, 1.0), randfn(0.0, 1.0)) * pose_jitter)
	var pose := Transform3D(code.basis * tilt, code.origin + jitter)
	_tracker.set_pose(&"default", pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	_tracker.spatial_tracking_state = OpenXRSpatialEntityTracker.ENTITY_TRACKING_STATE_TRACKING


## Where the printed code is, in tracking space.
func _code_transform() -> Transform3D:
	var placed := real_site * _marker.global_transform.orthonormalized()
	return placed * code_error if _misplaced else placed


func _place_code() -> void:
	# Just off the wall so the scan doesn't hide it.
	_code.transform = _code_transform() * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.003))


func _update_view() -> void:
	_reality.visible = _view != 2
	_checker.visible = _view == 2
	_ar.visible = _view != 1


func _update_help() -> void:
	var code_state := "non vu"
	if _code_seen_at >= 0.0:
		code_state = "vu à %.1f m" % _code_seen_at
		if _code_seen_at > _session.max_marker_distance:
			code_state += " (approchez-vous à moins de %.0f m pour caler)" % _session.max_marker_distance
	var room_state := "calée sur le QR code" if _session.is_aligned() else "en attente du QR code"
	var lines: Array[String] = [
		"Démo AR sans casque",
		"Vue (Tab) : %s" % VIEWS[_view],
		"QR code : %s" % code_state,
		"Visite : %s" % room_state,
		"Code collé de travers (G) : %s" % ("oui" if _misplaced else "non"),
		"",
		"ZQSD / WASD : marcher — A/E : descendre/monter — Maj : courir",
		"1 à 3 : aller au %s" % ", au ".join(PackedStringArray(STATIONS.map(func(station: Dictionary) -> String: return station.name))),
		"Clic gauche glissé : regarder — Clic droit : creuser le mur",
	]
	if _session.is_calibrating():
		lines.append("Calibration : flèches = déplacer, Page préc./suiv. = hauteur, Début/Fin = tourner, Retour arrière = réinitialiser, C = valider")
	else:
		lines.append("C : calibrer — H : masquer l'aide — R : recommencer")
	_help.text = "\n".join(lines)


## A QR-looking code: finder squares in three corners, timing lines, and
## modules made up from the marker's text.
func _code_mesh() -> QuadMesh:
	var size := CODE_MODULES + CODE_QUIET_ZONE * 2
	var image := Image.create(size, size, false, Image.FORMAT_L8)
	image.fill(Color.WHITE)
	var random := RandomNumberGenerator.new()
	random.seed = hash(_marker.data)
	var finders: Array[Vector2i] = [Vector2i(0, 0), Vector2i(CODE_MODULES - 7, 0), Vector2i(0, CODE_MODULES - 7)]
	for y in CODE_MODULES:
		for x in CODE_MODULES:
			var dark := random.randf() < 0.5
			for finder in finders:
				var local := Vector2i(x, y) - finder
				if local.x >= -1 and local.y >= -1 and local.x <= 7 and local.y <= 7:
					var ring := maxi(absi(local.x - 3), absi(local.y - 3))
					dark = ring != 2 and ring != 4
			var timing := (y == 6 and x > 7 and x < CODE_MODULES - 8) \
					or (x == 6 and y > 7 and y < CODE_MODULES - 8)
			if timing:
				dark = (x + y) % 2 == 0
			if dark:
				image.set_pixel(x + CODE_QUIET_ZONE, y + CODE_QUIET_ZONE, Color.BLACK)
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var mesh := QuadMesh.new()
	mesh.size = Vector2(_marker.size, _marker.size)
	mesh.material = material
	return mesh
