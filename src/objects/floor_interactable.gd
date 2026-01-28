# Floor Interactable
# Example of using BaseInteractable to respond to interactions
# Changes floor color when selected/activated
extends BaseInteractable

@onready var _mesh_inst: MeshInstance3D = get_parent().get_node_or_null("MeshInstance3D") as MeshInstance3D


func _ready() -> void:
	super._ready()
	
	# Configure interactable
	interaction_layers = 1 << 5  # Layer 6
	highlight_on_hover = true
	
	# Connect to activation signal for immediate response
	activated.connect(_on_activated_signal)


func _on_activated_signal(_interactor: BaseInteractor) -> void:
	"""Called when interactor activates this (e.g., button press)"""
	_change_floor_color()


func _on_select_started(interactor: BaseInteractor) -> void:
	"""Override base method - called when selected"""
	super._on_select_started(interactor)
	# Also change color on select
	_change_floor_color()


func _change_floor_color() -> void:
	"""Change the floor material to a random color"""
	if not _mesh_inst:
		# fallback: try to find a MeshInstance3D child at runtime
		var parent = get_parent()
		if parent:
			_mesh_inst = parent.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if not _mesh_inst:
			return
	
	var mat: StandardMaterial3D = _mesh_inst.material_override as StandardMaterial3D
	if not mat:
		mat = StandardMaterial3D.new()
		_mesh_inst.material_override = mat
	
	# Choose a random color
	var chosen_color: Color = Color(randf(), randf(), randf(), 1.0)
	mat.albedo_color = chosen_color
	print("FloorInteractable: Changed color to ", chosen_color)
