class_name ARSession
extends Node

## Runs its room in AR when [member AppMode.mode] is AR, and does nothing in VR.
##
## Turns passthrough on and lines the room up with the real site: each
## [QRMarker] in the room marks where a printed QR code is stuck on the real
## walls, and when the headset sees one, the [XROrigin3D] is placed so the code
## on the scan lands on the real one. The whole room then sits on the real site,
## pipes and water included. The scan itself isn't drawn: [HandDissolve] turns
## it into an invisible mask hiding what the real walls hide, and still opens
## holes in it.
##
## The player walks instead of moving with the controllers: the [member vr_only]
## nodes are turned off. The room's [member content] stays hidden until a code
## has been seen, so it never shows at the wrong place.
##
## The origin stays upright and only follows codes near the head, where their
## pose is good. What is left of the misalignment can be corrected in the
## headset: Y on the left controller toggles calibration, where the scan shows
## over passthrough and the sticks move it (left: across, right: up and down,
## and turn around the first marker); B on the right controller resets. The
## correction is saved per room in [constant CALIBRATION_FILE].

const CALIBRATION_FILE := "user://ar_calibration.cfg"
const STICK_DEADZONE := 0.15
## How long the status stays once the room is lined up, in seconds.
const STATUS_DURATION := 4.0

@export var start_xr: XRToolsStartXR
@export var xr_origin: XROrigin3D
@export var camera: XRCamera3D
@export var hand_dissolve: HandDissolve
@export var world_environment: WorldEnvironment
@export var left_controller: XRController3D
@export var right_controller: XRController3D

## Nodes only used in VR, like movement: those with an [code]enabled[/code]
## property get it turned off, the others stop processing.
@export var vr_only: Array[Node] = []

## Nodes hidden until a code has been seen.
@export var content: Array[Node3D] = []

## Furthest from the head a code is followed, in meters; the pose of a code
## further away is too rough.
@export_range(0.5, 10.0, 0.1, "suffix:m") var max_marker_distance := 3.0

## How fast the room follows a code it sees, once lined up; higher follows
## the code's pose quicker, lower averages away its jitter.
@export_range(0.1, 20.0, 0.1) var smoothing := 2.0

@export_group("Calibration")
## How fast the left stick moves the scan, in m/s.
@export_range(0.01, 1.0, 0.01, "suffix:m/s") var move_speed := 0.1
## How fast the right stick turns the scan, in degrees per second.
@export_range(0.1, 30.0, 0.1, "suffix:°/s") var turn_speed := 3.0
## Opacity of the scan over passthrough while calibrating.
@export_range(0.0, 1.0, 0.05) var scan_opacity := 0.5

var _markers: Array[QRMarker] = []
var _aligned := false
# Origin from the codes, before the calibration offset.
var _yaw := 0.0
var _position := Vector3.ZERO
# Calibration offset: the scan turned by _offset_yaw around the first marker,
# then moved by _offset_position.
var _offset_yaw := 0.0
var _offset_position := Vector3.ZERO
var _calibrating := false
var _status: Label3D
var _status_tween: Tween


func _ready() -> void:
	if not AppMode.is_ar():
		set_physics_process(false)
		return

	for node in get_parent().find_children("*", "Marker3D", true, false):
		if node is QRMarker:
			_markers.append(node)
	if _markers.is_empty():
		push_warning("ARSession: no QRMarker in %s, the scan can't be lined up." % get_parent().name)

	for node in vr_only:
		if "enabled" in node:
			node.enabled = false
		else:
			node.process_mode = PROCESS_MODE_DISABLED
	for node in content:
		node.visible = false

	_start_passthrough()
	RenderingServer.global_shader_parameter_set(&"PASSTHROUGH", true)
	hand_dissolve.mask_mode = true
	_load_calibration()
	_add_status()

	left_controller.button_pressed.connect(_on_left_button_pressed)
	right_controller.button_pressed.connect(_on_right_button_pressed)

	var origin := xr_origin.global_transform
	_yaw = origin.basis.get_euler().y
	_position = origin.origin
	# StartXR initializes before us; without a running interface (desktop),
	# no code will ever be seen: keep the room where it is.
	if not (start_xr.xr_interface and start_xr.xr_interface.is_initialized()):
		_set_aligned()
	else:
		_show_status("Regardez le QR code pour caler la visite sur le site.")


func _exit_tree() -> void:
	if AppMode.is_ar():
		RenderingServer.global_shader_parameter_set(&"PASSTHROUGH", false)


func _physics_process(delta: float) -> void:
	var seen: Variant = _origin_from_markers()
	if seen != null:
		var target: Transform3D = seen
		var target_yaw := target.basis.get_euler().y
		if not _aligned:
			_yaw = target_yaw
			_position = target.origin
			_set_aligned()
		else:
			var weight := 1.0 - exp(-smoothing * delta)
			_yaw = lerp_angle(_yaw, target_yaw, weight)
			_position = _position.lerp(target.origin, weight)

	if _calibrating:
		_calibrate(delta)
	if _aligned:
		# Every frame, so nothing else moves the origin away from the site.
		xr_origin.global_transform = _offset().affine_inverse() * Transform3D(Basis(Vector3.UP, _yaw), _position)


func _start_passthrough() -> void:
	var viewport := start_xr.get_xr_viewport()
	var xr_interface := start_xr.xr_interface
	if xr_interface and xr_interface.is_initialized():
		if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in xr_interface.get_supported_environment_blend_modes():
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		else:
			push_warning("ARSession: this headset has no passthrough.")
	# What is left transparent shows passthrough.
	viewport.transparent_bg = true
	if world_environment and world_environment.environment:
		# A copy: the room's environment is shared with its VR runs.
		var environment := world_environment.environment.duplicate() as Environment
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
		world_environment.environment = environment


## Origin that puts the closest code seen on its [QRMarker], or null.
func _origin_from_markers() -> Variant:
	var best: Variant = null
	var best_distance := max_marker_distance
	for tracker: XRTracker in XRServer.get_trackers(XRServer.TRACKER_ANCHOR).values():
		var marker_tracker := tracker as OpenXRMarkerTracker
		if not marker_tracker or marker_tracker.spatial_tracking_state != OpenXRSpatialEntityTracker.ENTITY_TRACKING_STATE_TRACKING:
			continue
		var marker := _marker_for(marker_tracker)
		var pose := marker_tracker.get_pose(&"default")
		if not marker or not pose or not pose.has_tracking_data:
			continue
		# In the origin's space, like the camera's local transform.
		var code := pose.get_adjusted_transform()
		var distance := camera.transform.origin.distance_to(code.origin)
		if distance < best_distance:
			best_distance = distance
			best = _origin_for(marker, code)
	return best


## The marker a code stands for: the one with its text, or else one matching
## any code.
func _marker_for(tracker: OpenXRMarkerTracker) -> QRMarker:
	if tracker.marker_type != OpenXRSpatialComponentMarkerList.MARKER_TYPE_QRCODE:
		return null
	var data: Variant = tracker.get_marker_data()
	var text: String = data.get_string_from_utf8() if data is PackedByteArray else str(data)
	var any: QRMarker = null
	for marker in _markers:
		if marker.data == text:
			return marker
		if marker.data.is_empty() and not any:
			any = marker
	return any


## Origin putting [param code], seen in the origin's space, on [param marker].
## Kept upright: tracking space and the room both stand on the floor, and a
## code's own tilt is rougher than its position.
func _origin_for(marker: QRMarker, code: Transform3D) -> Transform3D:
	var origin := marker.global_transform.orthonormalized() * code.affine_inverse()
	var back := origin.basis.z
	var basis := Basis(Vector3.UP, atan2(back.x, back.z))
	return Transform3D(basis, marker.global_position - basis * code.origin)


## Calibration offset, as how the scan is moved in the room.
func _offset() -> Transform3D:
	var pivot := _markers[0].global_position if _markers else Vector3.ZERO
	return Transform3D(Basis.IDENTITY, pivot + _offset_position) \
			* Transform3D(Basis(Vector3.UP, _offset_yaw), Vector3.ZERO) \
			* Transform3D(Basis.IDENTITY, -pivot)


func _set_aligned() -> void:
	_aligned = true
	for node in content:
		node.visible = true
	_show_status("Visite calée sur le site.\nY : corriger l'alignement.", STATUS_DURATION)


func _calibrate(delta: float) -> void:
	var move := _stick(left_controller)
	var lift_turn := _stick(right_controller)
	# Across, as the player sees it before the offset is applied.
	var view := (_offset().basis * camera.global_basis)
	var forward := Vector3(-view.z.x, 0.0, -view.z.z).normalized()
	var right := Vector3(view.x.x, 0.0, view.x.z).normalized()
	_offset_position += (right * move.x + forward * move.y) * move_speed * delta
	_offset_position.y += lift_turn.y * move_speed * delta
	_offset_yaw -= deg_to_rad(lift_turn.x * turn_speed) * delta


func _stick(controller: XRController3D) -> Vector2:
	var value := controller.get_vector2(&"primary")
	return value if value.length() > STICK_DEADZONE else Vector2.ZERO


func _set_calibrating(calibrating: bool) -> void:
	_calibrating = calibrating
	hand_dissolve.mask_preview = scan_opacity if calibrating else 0.0
	for marker in _markers:
		marker.preview_visible = calibrating
	if calibrating:
		_show_status("Calibration\nStick gauche : déplacer\nStick droit : monter, descendre, tourner\nB : réinitialiser — Y : valider")
	else:
		_save_calibration()
		_show_status("Alignement enregistré.", STATUS_DURATION)


func _on_left_button_pressed(action: String) -> void:
	if action == "by_button" and _aligned:
		_set_calibrating(not _calibrating)


func _on_right_button_pressed(action: String) -> void:
	if action == "by_button" and _calibrating:
		_offset_yaw = 0.0
		_offset_position = Vector3.ZERO


func _room_key() -> String:
	return get_tree().current_scene.scene_file_path if get_tree().current_scene else get_parent().name


func _load_calibration() -> void:
	var config := ConfigFile.new()
	if config.load(CALIBRATION_FILE) != OK:
		return
	_offset_yaw = config.get_value(_room_key(), "yaw", 0.0)
	_offset_position = config.get_value(_room_key(), "position", Vector3.ZERO)


func _save_calibration() -> void:
	var config := ConfigFile.new()
	config.load(CALIBRATION_FILE)
	config.set_value(_room_key(), "yaw", _offset_yaw)
	config.set_value(_room_key(), "position", _offset_position)
	var error := config.save(CALIBRATION_FILE)
	if error != OK:
		push_error("ARSession: couldn't save the calibration (%s)." % error_string(error))
	# To bake it into the room: move the markers by the inverse of this.
	print("ARSession: calibration of %s: yaw %.2f°, position %s" % [_room_key(), rad_to_deg(_offset_yaw), _offset_position])


func _add_status() -> void:
	_status = Label3D.new()
	_status.name = "ARStatus"
	_status.position = Vector3(0.0, -0.12, -0.7)
	_status.pixel_size = 0.0006
	_status.font_size = 48
	_status.outline_size = 12
	_status.no_depth_test = true
	_status.render_priority = Material.RENDER_PRIORITY_MAX
	_status.outline_render_priority = Material.RENDER_PRIORITY_MAX - 1
	_status.visible = false
	camera.add_child(_status)


## Shows [param text] in front of the player, for [param duration] seconds or
## until replaced when 0.
func _show_status(text: String, duration := 0.0) -> void:
	if _status_tween:
		_status_tween.kill()
	_status.text = text
	_status.visible = true
	if duration > 0.0:
		_status_tween = create_tween()
		_status_tween.tween_interval(duration)
		_status_tween.tween_callback(_status.hide)
