# Meta Store Trigger (Grabbable)
# Opens the Meta Horizon Store product details page when grabbed.
extends Grabbable

## The Meta App ID (Item ID) of the product to show.
@export var item_id: String = "32841847922127286"

func _ready() -> void:
	super._ready()
	
	# Connect to the grabbed signal from the base class
	grabbed.connect(_on_grabbed)


func _on_grabbed(_hand: RigidBody3D) -> void:
	"""Called when the object is grabbed by a VR hand"""
	_open_meta_store()


func _open_meta_store() -> void:
	"""Opens the Meta Horizon Store to the specified item_id"""
	if item_id == "" or item_id == "32841847922127286_PLACEHOLDER": # Safety check
		push_warning("MetaStoreTrigger: No valid item_id set.")
		return

	# URI-only flow (no Meta Platform SDK dependency).
	var uris := [
		"oculus://store/apps/details?id=" + item_id,
		"oculus://item/" + item_id,
		"https://www.meta.com/experiences/" + item_id + "/",
		"https://www.oculus.com/experiences/quest/" + item_id + "/"
	]

	for uri in uris:
		print("MetaStoreTrigger: Attempting URI: ", uri)
		var err := OS.shell_open(uri)
		if err == OK:
			print("MetaStoreTrigger: URI opened successfully: ", uri)
			return

	push_error("MetaStoreTrigger: Failed to open Meta store page for item_id=", item_id)
