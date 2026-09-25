extends Node

## Places the player on the scan's floor at the spawn point once tracking has
## started, and puts them back there if they ever fall out of the world.
##
## Where the player physically stands, and the floor height the headset
## reports, vary between sessions (e.g. stationary boundary with a guessed
## floor). Snapping to the real floor under the spawn point makes the start
## independent of both.

## Player body to place.
@export var player_body: XRToolsPlayerBody

## Spawn point; only its position and yaw are used.
@export var spawn: Node3D

## Emits [signal XRToolsStartXR.xr_started] once tracking is live.
@export var start_xr: XRToolsStartXR

## Physics layers treated as floor.
@export_flags_3d_physics var floor_mask := 1

## How far below the spawn point counts as having fallen out of the world.
@export var fall_limit := 10.0

## Height above the floor to place the player, who then settles onto it.
## Placing the body exactly on the double-sided scan collision can push it
## through the floor.
@export var drop_height := 0.1

var _spawn_transform: Transform3D
var _placed := false


func _ready() -> void:
	_spawn_transform = spawn.global_transform
	# StartXR initializes before us; without a running interface (desktop),
	# there is no tracking to wait for.
	var xr_running := start_xr and start_xr.xr_interface and start_xr.xr_interface.is_initialized()
	if xr_running and not XRToolsStartXR.is_xr_active():
		start_xr.xr_started.connect(_on_xr_started, CONNECT_ONE_SHOT)
	else:
		_on_xr_started()


func _physics_process(_delta: float) -> void:
	if _placed and player_body.global_position.y < _spawn_transform.origin.y - fall_limit:
		push_warning("Player fell out of the world at %s, respawning." % player_body.global_position)
		respawn()


## Puts the player on the floor at the spawn point.
func respawn() -> void:
	var target := _spawn_transform
	var up := Vector3.UP
	var from := target.origin + up * 2.0
	var query := PhysicsRayQueryParameters3D.create(from, target.origin - up * 2.0, floor_mask)
	query.exclude = [player_body.get_rid()]
	var hit := player_body.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		target.origin = hit.position + up * drop_height
	# Keep only the spawn's yaw so the player stands upright.
	var forward := -target.basis.z
	target.basis = Basis.looking_at(Vector3(forward.x, 0.0, forward.z).normalized(), up)
	player_body.teleport(target)


func _on_xr_started() -> void:
	# Wait for the tracked head pose to reach the body before placing it.
	await get_tree().physics_frame
	await get_tree().physics_frame
	respawn()
	_placed = true
