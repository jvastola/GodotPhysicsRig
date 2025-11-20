# Standalone QWERTY Keyboard Usage Guide

## Overview

The `KeyboardQWERTY` component is a fully-featured, reusable virtual keyboard that can be used anywhere in your Godot project. It supports:

- Full QWERTY layout
- Uppercase/lowercase letters with Shift and Caps Lock
- Numbers (0-9)
- Symbols (!@#$%^&*() and more)
- Configurable max length
- Multiple signals for flexibility

## Quick Start

### Basic Usage

```gdscript
# Load the keyboard scene
var keyboard_scene = preload("res://src/ui/KeyboardQWERTY.tscn")
var keyboard = keyboard_scene.instantiate()

# Add to your scene
add_child(keyboard)

# Connect to signals
keyboard.text_changed.connect(_on_keyboard_text_changed)
keyboard.text_submitted.connect(_on_keyboard_text_submitted)

func _on_keyboard_text_changed(text: String) -> void:
	print("Current text: ", text)

func _on_keyboard_text_submitted(text: String) -> void:
	print("Submitted text: ", text)
	# Do something with the text
	keyboard.clear()
```

### Configuration

```gdscript
# Configure the keyboard
keyboard.max_length = 20  # Limit to 20 characters (0 = unlimited)
keyboard.placeholder_text = "Enter your name..."
keyboard.allow_numbers = true
keyboard.allow_symbols = true
```

## Signals

### `text_changed(text: String)`
Emitted every time a character is added or removed.

**Use case:** Real-time text validation, live search, character counter

```gdscript
keyboard.text_changed.connect(func(text: String):
	character_count_label.text = str(text.length()) + "/50"
)
```

### `text_submitted(text: String)`
Emitted when the user presses Enter.

**Use case:** Form submission, search execution, confirming input

```gdscript
keyboard.text_submitted.connect(func(text: String):
	if text.length() >= 6:
		join_room(text)
	else:
		show_error("Room code must be 6 characters")
)
```

### `text_cleared()`
Emitted when the Clear button is pressed.

**Use case:** Resetting forms, canceling input

```gdscript
keyboard.text_cleared.connect(func():
	print("Keyboard cleared")
	reset_form()
)
```

## Public Methods

### `get_text() -> String`
Get the current text in the keyboard.

```gdscript
var current_text = keyboard.get_text()
print("Current: ", current_text)
```

### `set_text(text: String) -> void`
Set the keyboard text programmatically.

```gdscript
keyboard.set_text("HELLO")
# This will also emit text_changed signal
```

### `clear() -> void`
Clear all text from the keyboard.

```gdscript
keyboard.clear()
# This will emit both text_cleared and text_changed signals
```

## Example: Room Code Entry

```gdscript
extends Control

@onready var keyboard: Control = $KeyboardQWERTY
@onready var status_label: Label = $StatusLabel

func _ready() -> void:
	keyboard.max_length = 6  # Room codes are 6 characters
	keyboard.placeholder_text = "Enter room code"
	keyboard.allow_symbols = false  # Room codes don't use symbols
	
	keyboard.text_changed.connect(_on_code_changed)
	keyboard.text_submitted.connect(_on_code_submitted)

func _on_code_changed(text: String) -> void:
	# Convert to uppercase for room codes
	if text != text.to_upper():
		keyboard.set_text(text.to_upper())
	
	# Show character count
	status_label.text = str(text.length()) + "/6"

func _on_code_submitted(code: String) -> void:
	if code.length() == 6:
		status_label.text = "Joining room " + code + "..."
		NetworkManager.join_by_room_code(code)
	else:
		status_label.text = "Room code must be 6 characters!"
```

## Example: Text Input with Validation

```gdscript
extends Control

@onready var keyboard: Control = $KeyboardQWERTY

func _ready() -> void:
	keyboard.max_length = 20
	keyboard.placeholder_text = "Username (3-20 chars)"
	
	keyboard.text_changed.connect(_validate_username)
	keyboard.text_submitted.connect(_submit_username)

func _validate_username(username: String) -> void:
	if username.length() < 3:
		set_display_color(Color.RED)
	elif username.length() >= 3 and username.length() <= 20:
		set_display_color(Color.GREEN)

func _submit_username(username: String) -> void:
	if username.length() >= 3:
		print("Valid username: ", username)
		# Save username
		keyboard.clear()
	else:
		print("Username too short!")

func set_display_color(color: Color) -> void:
	keyboard.display_label.add_theme_color_override("font_color", color)
```

## Styling

The keyboard creates buttons dynamically, but you can customize their appearance by applying themes:

```gdscript
# Create a theme for the keyboard
var theme = Theme.new()

# Customize button style
var button_style = StyleBoxFlat.new()
button_style.bg_color = Color(0.2, 0.2, 0.3)
button_style.corner_radius_top_left = 5
button_style.corner_radius_top_right = 5
button_style.corner_radius_bottom_left = 5
button_style.corner_radius_bottom_right = 5

theme.set_stylebox("normal", "Button", button_style)

# Apply theme
keyboard.theme = theme
```

## 3D/VR Integration

To use the keyboard in a 3D/VR context:

1. Create a `SubViewport` with the keyboard
2. Display the viewport on a 3D plane
3. Use raycasting to detect button presses

Example:

```gdscript
# In your 3D scene
var viewport = SubViewport.new()
viewport.size = Vector2i(1024, 512)
viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

var keyboard = preload("res://src/ui/KeyboardQWERTY.tscn").instantiate()
viewport.add_child(keyboard)

# Create a mesh to display the viewport
var mesh_instance = MeshInstance3D.new()
var quad_mesh = QuadMesh.new()
quad_mesh.size = Vector2(2, 1)
mesh_instance.mesh = quad_mesh

# Apply viewport texture
var material = StandardMaterial3D.new()
material.albedo_texture = viewport.get_texture()
mesh_instance.material_override = material
```

## Tips

- **Case Sensitivity**: Use `set_text()` with `.to_upper()` or `.to_lower()` if you need forced case
- **Performance**: The keyboard is lightweight and rebuilds its layout on `_ready()`
- **Accessibility**: All buttons have clear labels and visual feedback
- **Reusability**: You can have multiple keyboard instances in the same scene

## Differences from `virtual_keyboard_2d.gd`

The old keyboard was limited to room code entry. This new keyboard:

- ✅ Full alphabet (not just subset)
- ✅ Lowercase and uppercase support
- ✅ Numbers and symbols
- ✅ Unlimited or custom max length
- ✅ Multiple signals (not just one)
- ✅ Reusable component design
- ✅ Better visual feedback
- ✅ Public API for programmatic control
