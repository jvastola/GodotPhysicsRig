# Base Interactable
# Base class for all objects that can be interacted with
extends Node
class_name BaseInteractable

enum SelectMode {
	SINGLE,    # Only one interactor can select at a time
	MULTIPLE   # Multiple interactors can select simultaneously
}

## Emitted when an interactor hovers over this interactable
signal hovered(interactor: BaseInteractor)
## Emitted when an interactor stops hovering
signal unhovered(interactor: BaseInteractor)
## Emitted when an interactor selects this interactable
signal selected(interactor: BaseInteractor)
## Emitted when an interactor deselects this interactable
signal deselected(interactor: BaseInteractor)
## Emitted when an interactor activates this interactable
signal activated(interactor: BaseInteractor)

@export_flags_3d_physics var interaction_layers: int = 1 << 5  # Layer 6 for interactables
@export var select_mode: SelectMode = SelectMode.SINGLE
@export var highlight_on_hover: bool = true
@export var enabled: bool = true

# Interaction state
var hovering_interactors: Array[BaseInteractor] = []
var selecting_interactors: Array[BaseInteractor] = []

# Visual feedback
var _original_materials: Dictionary = {}


func _ready() -> void:
	# Register with interaction manager
	if InteractionManager:
		InteractionManager.register_interactable(self)
	
	# Store original materials for highlight restoration
	_store_original_materials()


func _exit_tree() -> void:
	# Unregister from interaction manager
	if InteractionManager:
		InteractionManager.unregister_interactable(self)


## Check if this interactable can interact with the given interactor
func _can_interact_with(interactor: BaseInteractor) -> bool:
	if not enabled:
		return false
	
	# Check layer mask compatibility
	if (interaction_layers & interactor.interaction_layer_mask) == 0:
		return false
	
	return true


## Check if this interactable can be selected by the given interactor
func _can_select(_interactor: BaseInteractor) -> bool:
	if select_mode == SelectMode.SINGLE and not selecting_interactors.is_empty():
		# Already selected by another interactor
		return false
	
	return true


## Called when an interactor starts hovering
func _on_hover_entered(interactor: BaseInteractor) -> void:
	if not hovering_interactors.has(interactor):
		hovering_interactors.append(interactor)
	
	if highlight_on_hover and hovering_interactors.size() == 1:
		_apply_hover_highlight()
	
	hovered.emit(interactor)


## Called when an interactor stops hovering
func _on_hover_exited(interactor: BaseInteractor) -> void:
	hovering_interactors.erase(interactor)
	
	if highlight_on_hover and hovering_interactors.is_empty():
		_remove_hover_highlight()
	
	unhovered.emit(interactor)


## Called when an interactor selects this interactable
func _on_select_started(interactor: BaseInteractor) -> void:
	if not selecting_interactors.has(interactor):
		selecting_interactors.append(interactor)
	
	selected.emit(interactor)


## Called when an interactor deselects this interactable
func _on_select_ended(interactor: BaseInteractor) -> void:
	selecting_interactors.erase(interactor)
	deselected.emit(interactor)


## Called when an interactor activates this interactable
func _on_activated(interactor: BaseInteractor) -> void:
	activated.emit(interactor)


## Store original materials for hover highlight
func _store_original_materials() -> void:
	var parent = get_parent()
	if not parent:
		return
	
	for child in parent.get_children():
		if child is MeshInstance3D:
			var mesh_inst = child as MeshInstance3D
			# Store both material_override and surface materials
			if mesh_inst.material_override:
				_original_materials[mesh_inst] = {
					"override": mesh_inst.material_override,
					"surface": null
				}
			elif mesh_inst.mesh and mesh_inst.mesh.get_surface_count() > 0:
				_original_materials[mesh_inst] = {
					"override": null,
					"surface": mesh_inst.mesh.surface_get_material(0)
				}


## Apply hover highlight effect
func _apply_hover_highlight() -> void:
	var parent = get_parent()
	if not parent:
		return
	
	for child in parent.get_children():
		if child is MeshInstance3D:
			var mesh_inst = child as MeshInstance3D
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(1.2, 1.2, 1.0, 1.0)  # Slight yellow tint
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.2, 0.1)
			mesh_inst.material_override = mat


## Remove hover highlight effect
func _remove_hover_highlight() -> void:
	for mesh_inst in _original_materials:
		if is_instance_valid(mesh_inst):
			var data = _original_materials[mesh_inst]
			if data["override"]:
				mesh_inst.material_override = data["override"]
			else:
				mesh_inst.material_override = null


## Check if currently being hovered by any interactor
func is_hovered() -> bool:
	return not hovering_interactors.is_empty()


## Check if currently selected by any interactor
func is_selected() -> bool:
	return not selecting_interactors.is_empty()


## Get the collider node for physics-based interaction
## Override this if the interactable's collision is on a different node
func get_collider() -> CollisionObject3D:
	var parent = get_parent()
	if parent is CollisionObject3D:
		return parent as CollisionObject3D
	return null
