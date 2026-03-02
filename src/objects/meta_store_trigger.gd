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
	
	# oculus://item/[ID] is the most direct way to open the store page on Quest
	var primary_uri = "oculus://item/" + item_id
	# Various web fallbacks just in case
	var fallback_uris = [
		"https://www.meta.com/experiences/" + item_id + "/",
		"https://www.oculus.com/experiences/quest/" + item_id + "/"
	]
	
	print("MetaStoreTrigger: Attempting primary URI: ", primary_uri)
	
	# OS.shell_open returns an Error enum.
	var err = OS.shell_open(primary_uri)
	
	if err != OK:
		print("MetaStoreTrigger: Primary URI failed (Error ", err, "). Attempting fallbacks...")
		for fallback_uri in fallback_uris:
			print("MetaStoreTrigger: Trying fallback: ", fallback_uri)
			err = OS.shell_open(fallback_uri)
			if err == OK:
				print("MetaStoreTrigger: Fallback URI opened successfully: ", fallback_uri)
				return
		
		push_error("MetaStoreTrigger: All URI attempts failed. Final error code: ", err)
	else:
		print("MetaStoreTrigger: Primary URI opened successfully.")
