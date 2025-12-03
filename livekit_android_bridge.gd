# LiveKit Bridge: Rust on Desktop, Android Plugin on Mobile (same API)
extends Node

@export var server_url: String = "ws://localhost:7880"
@export var token: String = ""
var livekit: Node

signal room_connected
signal room_disconnected
signal participant_joined(identity: String)
signal participant_left(identity: String)
signal data_received(identity: String, data: PackedByteArray, topic: String)
signal audio_frame(identity: String, frame: PackedFloat32Array) # Stub for now

func _ready():
	if OS.get_name() == "Android":
		if Engine.has_singleton("GodotLiveKit"):
			livekit = Engine.get_singleton("GodotLiveKit")
			livekit.room_connected.connect(func(): room_connected.emit())
			livekit.participant_joined.connect(func(id): participant_joined.emit(id))
			# ... connect other signals
			print("✅ LiveKit Android Plugin loaded")
		else:
			push_error("GodotLiveKit singleton missing - check plugin/AAR")
	else:
		# Load Rust GDExtension (addons/godot-livekit)
		livekit = preload("res://addons/godot-livekit/livekit_client.gd").new() # Adjust path
		add_child(livekit)
		livekit.room_connected.connect(room_connected)
		# ...
		print("✅ LiveKit Rust GDExtension loaded")

func connect_to_room(url: String, token: String):
	livekit.connect_to_room(url, token)

func disconnect_from_room():
	livekit.disconnect_from_room()

func is_room_connected() -> bool:
	return livekit.is_room_connected()

func get_participant_identities() -> PackedStringArray:
	return livekit.get_participant_identities() if has_method("get_participant_identities") else PackedStringArray()

func send_data(data: PackedByteArray, topic: String = ""):
	livekit.send_data(data, topic)

# Usage: add this Node to scene, set url/token, call connect_to_room