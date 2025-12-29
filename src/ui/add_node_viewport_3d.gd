extends "res://src/ui/ui_viewport_3d.gd"

# Add Node Viewport 3D - 3D worldspace panel for adding nodes
# Inherits from UIViewport3D for pointer interaction and resizing


func _ready() -> void:
	# Call super._ready() to initialize UIViewport3D features (resizing handles, etc)
	super._ready()
	
	if viewport:
		# Connect close signal from UI
		var add_node_ui = viewport.get_node_or_null("AddNodeUI")
		if add_node_ui and add_node_ui.has_signal("close_requested"):
			add_node_ui.close_requested.connect(_on_close_requested)


func _on_close_requested() -> void:
	var panel_manager := UIPanelManager.find()
	if panel_manager:
		panel_manager.close_panel(name)
	else:
		queue_free()
