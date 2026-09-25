extends Node3D

@onready var gaze_ray: RayCast3D = get_node("../XROrigin3D/XRCamera3D/GazeRay")
@onready var info_panel: Node3D = $InfoPanel
@onready var icon: Sprite3D = $Icon

var is_looked_at := false


func _ready() -> void:
	# Le panneau est caché au démarrage
	info_panel.visible = false
	info_panel.scale = Vector3(0.01, 0.01, 0.01)

	# L'icône est visible au démarrage
	icon.visible = true


func _process(_delta: float) -> void:
	var looking_at_me := false

	if gaze_ray.is_colliding():
		var object = gaze_ray.get_collider()

		if object == $Area3D:
			looking_at_me = true

	if looking_at_me != is_looked_at:
		is_looked_at = looking_at_me

		if is_looked_at:
			show_info()
		else:
			hide_info()


func show_info() -> void:
	# Faire disparaître l'icône
	icon.visible = false

	# Afficher le panneau puis l'agrandir
	info_panel.visible = true

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		info_panel,
		"scale",
		Vector3(1, 1, 1),
		0.3
	)


func hide_info() -> void:
	# Réduire le panneau
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_IN)

	tween.tween_property(
		info_panel,
		"scale",
		Vector3(0.01, 0.01, 0.01),
		0.2
	)

	# Une fois le tween terminé, on cache vraiment le panneau
	tween.tween_callback(func(): info_panel.visible = false)

	# Faire réapparaître l'icône
	icon.visible = true
