Dev Mode Play/Pause Feature for Debug Console
Add a play/pause toggle to the debug console that pauses physics simulation while allowing developer interaction for object positioning.

User Review Required
IMPORTANT

This feature introduces a "dev mode" concept where physics is frozen but the player can still interact. This is different from Godot's built-in SceneTree.paused which pauses everything.

Design Decision: We'll use RigidBody3D.freeze to pause physics objects individually rather than get_tree().paused. This allows:

Player hands to continue following VR controllers
Grabbables to be picked up and positioned
UI to remain interactive
Other systems (networking, audio) to continue running
Proposed Changes
DevModeManager (New Autoload)
A new autoload singleton to manage the dev mode state globally.

[NEW] 
dev_mode_manager.gd
# Manages dev mode (physics pause) state globally
# - Pauses physics simulation for objects in "pausable" group
# - Keeps player/hands interactive
# - Provides signals for state changes
extends Node
signal dev_mode_changed(enabled: bool)
var is_dev_mode := false
func toggle_dev_mode() -> void
func set_dev_mode(enabled: bool) -> void
func _apply_dev_mode() -> void
Features:

Toggle dev mode on/off
Freeze all RigidBody3D nodes in "pausable" group
Exclude player body and physics hands from pause
Emit signal for UI updates
Debug Console UI Updates
Add a play/pause button to the existing debug console.

[MODIFY] 
DebugConsoleUI.tscn
Add a new button row above the filter controls:

HBoxContainer with play/pause button
Button text toggles between "⏸️ Pause" and "▶️ Play"
[MODIFY] 
debug_console_ui.gd
+# Dev mode toggle
+@onready var dev_mode_button: Button = $MarginContainer/VBoxContainer/HBoxContainer2/DevModeButton
func _ready() -> void:
    # ... existing code ...
+   _setup_dev_mode_button()
+   if DevModeManager:
+       DevModeManager.dev_mode_changed.connect(_on_dev_mode_changed)
+func _setup_dev_mode_button() -> void:
+   if dev_mode_button:
+       dev_mode_button.pressed.connect(_on_dev_mode_pressed)
+       _update_dev_mode_button(false)
+func _on_dev_mode_pressed() -> void:
+   if DevModeManager:
+       DevModeManager.toggle_dev_mode()
+func _on_dev_mode_changed(enabled: bool) -> void:
+   _update_dev_mode_button(enabled)
+   if enabled:
+       log_system("Dev Mode: PAUSED - Physics frozen, positioning enabled")
+   else:
+       log_system("Dev Mode: PLAYING - Physics resumed")
+func _update_dev_mode_button(paused: bool) -> void:
+   if dev_mode_button:
+       dev_mode_button.text = "▶️ Play" if paused else "⏸️ Pause"
Grabbable Updates
Make grabbables work in dev mode by checking pause state.

[MODIFY] 
grabbable.gd
func _ready() -> void:
    # ... existing code ...
+   # Add to pausable group for dev mode
+   add_to_group("pausable")
func release() -> void:
    # ... existing release logic ...
+   # In dev mode, keep object frozen after release for positioning
+   if DevModeManager and DevModeManager.is_dev_mode:
+       freeze = true
Project Configuration
Register the new autoload.

[MODIFY] 
project.godot
[autoload]
GameManager="*res://src/systems/game_manager.gd"
SaveManager="*res://src/systems/save_manager.gd"
+DevModeManager="*res://src/systems/dev_mode_manager.gd"
InventoryManager="*res://src/systems/inventory_manager.gd"
Verification Plan
Manual Verification
Toggle Test

Open debug console in VR
Click Pause button
Verify button text changes to "▶️ Play"
Verify console shows "Dev Mode: PAUSED" message
Physics Freeze Test

Drop a grabbable object
Activate dev mode
Verify the object stops mid-air if falling
Verify it doesn't respond to physics
Interaction Test

In dev mode, verify:
Player can still move
Hands still follow controllers
Can grab frozen objects
Can position them in 3D space
Releasing object leaves it in place
Resume Test

Click Play button
Verify objects resume physics
Verify frozen objects fall/respond normally
Edge Cases
Objects grabbed before pause should work normally
Scene transitions should reset dev mode state
Multiple toggle doesn't cause issues