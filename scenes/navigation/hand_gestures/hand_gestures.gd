extends Node

const ACTION := &"gesture_select"
const HAND_PROFILE := "/interaction_profiles/ext/hand_interaction_ext"
const HAND_TRACKERS := {
	&"left_hand": &"/user/hand_tracker/left",
	&"right_hand": &"/user/hand_tracker/right",
}

var pinch_start := 0.02
var pinch_end := 0.035
var min_index_to_palm := 0.06
var hold_time := 0.15
var open_time := 0.3
var debug := false

var _states := {}
var _debug_timer := 0.0


class HandState:
	var armed := false
	var open_for := 0.0
	var pinch_for := 0.0
	var pressed := false


func _ready() -> void:
	get_tree().scene_changed.connect(_reset)


func _reset() -> void:
	for controller_name: StringName in HAND_TRACKERS:
		var controller := XRServer.get_tracker(controller_name) as XRControllerTracker
		if controller:
			controller.set_input(ACTION, false)
	_states.clear()


func _process(delta: float) -> void:
	_debug_timer += delta
	for controller_name: StringName in HAND_TRACKERS:
		var controller := XRServer.get_tracker(controller_name) as XRControllerTracker
		if not controller:
			continue
		var state: HandState = _states.get_or_add(controller_name, HandState.new())
		var pressed := false
		if controller.profile == HAND_PROFILE:
			var hand := XRServer.get_tracker(HAND_TRACKERS[controller_name]) as XRHandTracker
			pressed = _update_hand(state, hand, delta, controller_name)
		else:
			state.armed = false
			pressed = controller.get_input(&"trigger_click") == true
		if pressed != state.pressed:
			state.pressed = pressed
			controller.set_input(ACTION, pressed)
	if _debug_timer >= 0.5:
		_debug_timer = 0.0


func _update_hand(state: HandState, hand: XRHandTracker, delta: float, controller_name: StringName) -> bool:
	var joints := [XRHandTracker.HAND_JOINT_THUMB_TIP, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP, XRHandTracker.HAND_JOINT_PALM]
	if not hand or not hand.has_tracking_data:
		state.armed = false
		state.open_for = 0.0
		state.pinch_for = 0.0
		return false
	for joint in joints:
		if not hand.get_hand_joint_flags(joint) & XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID:
			return state.pressed
	var thumb := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
	var index := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP).origin
	var palm := hand.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
	var pinch := thumb.distance_to(index)
	var fist := index.distance_to(palm) < min_index_to_palm

	if debug and _debug_timer >= 0.5:
		print("HandGestures %s pinch=%.3f index_palm=%.3f fist=%s armed=%s pressed=%s" % [controller_name, pinch, index.distance_to(palm), fist, state.armed, state.pressed])

	if not state.armed:
		state.open_for = state.open_for + delta if pinch > pinch_end and not fist else 0.0
		state.armed = state.open_for >= open_time
		return false

	if state.pressed:
		if fist:
			_cancel_teleport(controller_name)
			state.armed = false
			state.open_for = 0.0
			state.pinch_for = 0.0
			return false
		if pinch < pinch_end:
			return true
		state.pinch_for = 0.0
		return false

	state.pinch_for = state.pinch_for + delta if pinch < pinch_start and not fist else 0.0
	return state.pinch_for >= hold_time


func _cancel_teleport(controller_name: StringName) -> void:
	var scene := get_tree().current_scene
	if not scene:
		return
	for controller: XRController3D in scene.find_children("*", "XRController3D", true, false):
		if controller.tracker != controller_name:
			continue
		for child in controller.get_children():
			if child is XRToolsFunctionTeleport:
				_restart(child)


func _restart(teleport: XRToolsFunctionTeleport) -> void:
	teleport.enabled = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	teleport.enabled = true
