class_name DrawNode
extends Node2D
## Node2D that delegates drawing to a callback (overlays, indicators).

var draw_func: Callable


func _draw() -> void:
	if draw_func.is_valid():
		draw_func.call(self)
