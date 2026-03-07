# Keyboard 3D Controller
# Manages a set of PokeableButtons and updates a Label3D with typed text
extends Node3D
class_name Keyboard3DController

@export var display_label_path: NodePath
@export var max_length: int = 20
@export var keypress_sound: AudioStream = preload("res://assets/audio/keypress.ogg")
@export var pitch_randomness: float = 0.15

var _display_label: Label3D
var _current_text: String = ""

func _ready() -> void:
	if not display_label_path.is_empty():
		_display_label = get_node(display_label_path)
		_display_label.text = "Type here..."
	
	# Connect all PokeableButton children
	_connect_buttons(self)


func _connect_buttons(root: Node) -> void:
	for child in root.get_children():
		if child is PokeableButton:
			child.pressed.connect(_on_key_pressed.bind(child.key_character))
			# Configure audio for each button
			if keypress_sound:
				child.press_sound = keypress_sound
				child.pitch_randomness = pitch_randomness
		
		# Recursive to find buttons in sub-containers
		if child.get_child_count() > 0:
			_connect_buttons(child)


func _on_key_pressed(character: String) -> void:
	if character == "BACK":
		if _current_text.length() > 0:
			_current_text = _current_text.left(_current_text.length() - 1)
	elif character == "SPACE":
		if _current_text.length() < max_length:
			_current_text += " "
	elif character == "ENTER":
		# Handle enter (e.g. submit or newline)
		_current_text = ""
	else:
		if _current_text.length() < max_length:
			_current_text += character
	
	_update_display()


func _update_display() -> void:
	if _display_label:
		if _current_text.is_empty():
			_display_label.text = "Type here..."
		else:
			_display_label.text = _current_text
