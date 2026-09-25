extends Area3D

@onready var water_sound: AudioStreamPlayer3D = $WaterSound

func _on_body_entered(body: Node3D) -> void:
	print("Entrée dans la zone :", body.name)
	water_sound.play()

func _on_body_exited(body: Node3D) -> void:
	print("Sortie de la zone :", body.name)
	water_sound.stop()
