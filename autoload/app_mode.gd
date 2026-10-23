extends Node

## How the app shows the site, chosen at launch in the welcome room.
##
## In VR the scans are the world. In AR the headset shows the real site through
## passthrough: a room's [ARSession] lines its scan up with the real walls using
## a QR code, and the scan is no longer drawn, it only hides what the real walls
## hide (pipes, water).

enum Mode { VR, AR }

var mode := Mode.VR


func is_ar() -> bool:
	return mode == Mode.AR
