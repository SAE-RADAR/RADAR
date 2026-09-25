@tool
class_name InfoBoxData
extends Resource

## Content shown by an [InfoBox]: a title, a short text, a list of key facts
## and an optional picture. Saved as its own resource so the same box can be
## reused for any place, and so the text can be edited without touching the
## scene.

@export var title := "":
	set(value):
		title = value
		emit_changed()

## Smaller line under the title, e.g. the period or the location.
@export var subtitle := "":
	set(value):
		subtitle = value
		emit_changed()

@export_multiline var description := "":
	set(value):
		description = value
		emit_changed()

## Label and value pairs listed under the description, in order.
@export var facts: Dictionary[String, String] = {}:
	set(value):
		facts = value
		emit_changed()

## Picture shown between the header and the description.
@export var image: Texture2D:
	set(value):
		image = value
		emit_changed()

## Credit shown in small print at the bottom.
@export var source := "":
	set(value):
		source = value
		emit_changed()
