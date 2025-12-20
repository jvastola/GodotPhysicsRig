extends "res://src/ui/ui_viewport_3d.gd"

## 3D viewport wrapper for the World Transcript Panel.
## Displays the transcript panel in VR/3D space with pointer interaction.

## Reference to the transcript panel inside the viewport
var transcript_panel: WorldTranscriptPanel

## Reference to the transcript store
var transcript_store: WorldTranscriptStore

## Reference to the transcript receiver
var transcript_receiver: TranscriptReceiverHandler


func _ready() -> void:
	super._ready()
	_setup_transcript_system()


func _setup_transcript_system() -> void:
	# Find the transcript panel in the viewport
	if viewport:
		transcript_panel = viewport.get_node_or_null("WorldTranscriptPanel") as WorldTranscriptPanel
	
	if not transcript_panel:
		push_warning("WorldTranscriptViewport3D: WorldTranscriptPanel not found in viewport")
		return
	
	# Create or find the transcript store
	transcript_store = get_node_or_null("WorldTranscriptStore") as WorldTranscriptStore
	if not transcript_store:
		transcript_store = WorldTranscriptStore.new()
		transcript_store.name = "WorldTranscriptStore"
		add_child(transcript_store)
	
	# Create or find the transcript receiver
	transcript_receiver = get_node_or_null("TranscriptReceiverHandler") as TranscriptReceiverHandler
	if not transcript_receiver:
		transcript_receiver = TranscriptReceiverHandler.new()
		transcript_receiver.name = "TranscriptReceiverHandler"
		add_child(transcript_receiver)
	
	# Wire up the components
	transcript_receiver.transcript_store = transcript_store
	transcript_panel.set_transcript_store(transcript_store)
	
	# Connect send to LLM signal
	transcript_panel.send_to_llm_requested.connect(_on_send_to_llm_requested)
	
	print("WorldTranscriptViewport3D: Transcript system initialized")


## Handle request to send text to LLM
func _on_send_to_llm_requested(text: String) -> void:
	# Find the LLM Chat Terminal and send the text
	var llm_terminal = _find_llm_terminal()
	if llm_terminal and llm_terminal.has_method("send_message"):
		llm_terminal.send_message(text)
	else:
		push_warning("WorldTranscriptViewport3D: LLM Chat Terminal not found")


## Find the LLM Chat Terminal in the scene
func _find_llm_terminal() -> Node:
	# Try to find via static instance on the script class
	var llm_script = load("res://src/ui/llm_chat_terminal_ui.gd")
	if llm_script and "instance" in llm_script:
		var inst = llm_script.get("instance")
		if inst and is_instance_valid(inst):
			return inst
	
	# Try to find in scene tree by group
	var terminals := get_tree().get_nodes_in_group("llm_chat_terminal")
	if not terminals.is_empty():
		return terminals[0]
	
	# Try to find by searching for the node type
	var root := get_tree().current_scene
	if root:
		var found := _find_node_by_script(root, llm_script)
		if found:
			return found
	
	return null


## Recursively find a node with a specific script
func _find_node_by_script(node: Node, script: Script) -> Node:
	if node.get_script() == script:
		return node
	for child in node.get_children():
		var found := _find_node_by_script(child, script)
		if found:
			return found
	return null


## Get the transcript store for external access
func get_transcript_store() -> WorldTranscriptStore:
	return transcript_store


## Get the transcript receiver for external access
func get_transcript_receiver() -> TranscriptReceiverHandler:
	return transcript_receiver


## Set the room name for export metadata
func set_room_name(room_name: String) -> void:
	if transcript_store:
		transcript_store.room_name = room_name


## Set the local user identity for marking local entries
func set_local_identity(identity: String) -> void:
	if transcript_receiver:
		transcript_receiver.set_local_identity(identity)


## Add a test entry (for debugging)
func add_test_entry(speaker: String, text: String, is_local: bool = false) -> void:
	if transcript_receiver:
		transcript_receiver.create_test_entry(speaker, text, is_local)
