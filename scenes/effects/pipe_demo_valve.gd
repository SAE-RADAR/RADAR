extends Node

## Turns a pipe's valve open and shut in a loop, for the pipe demo, and shows
## the speed on a label: the arrows slow down and stop without jumping.

@export var pipe: Pipe
@export var label: Label3D

## Speed with the valve wide open.
@export_range(0.0, 5.0, 0.05, "suffix:m/s") var max_speed := 1.2

## Time for a full open and shut cycle.
@export_range(1.0, 60.0, 0.5, "suffix:s") var period := 8.0

var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	# Held open, closing, held shut, opening.
	var opening := clampf(1.5 * sin(TAU * _time / period) + 0.5, 0.0, 1.0)
	pipe.flow_speed = max_speed * opening
	if pipe.flow_speed < 0.02:
		label.text = "Vanne fermée · eau immobile"
	else:
		label.text = "Vanne · %s m/s" % String.num(pipe.flow_speed, 2).replace(".", ",")
