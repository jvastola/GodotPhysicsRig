# Example: How to set up VR Hand with new Interaction System
# This is a reference guide for integrating ray and poke interactors with physics hands

## Setup for VR Hand (PhysicsHand.tscn or similar)

### 1. Add RayInteractor as child of XRController3D

```gdscript
# In physics_hand.gd or via scene tree:
var ray_interactor = RayInteractor.new()
ray_interactor.name = "RayInteractor"
target.add_child(ray_interactor)  # target is the XRController3D

# Configure ray interactor
ray_interactor.set_controller(target)
ray_interactor.select_action = "trigger_click"
ray_interactor.ray_length = 5.0
ray_interactor.show_ray = true
ray_interactor.show_hit_marker = true
```

### 2. Add PokeInteractor for fingertip (optional)

```gdscript
# Create a Node3D marker at fingertip position in your hand model
# Then add poke interactor:
var poke_interactor = PokeInteractor.new()
poke_interactor.name = "PokeInteractor"
target.add_child(poke_interactor)

# Configure poke interactor
poke_interactor.attach_transform_path = NodePath("HandModel/IndexFinger/Tip")
poke_interactor.poke_depth = 0.02
poke_interactor.show_debug_sphere = true  # For testing
```

### 3. Make objects interactable

For grabbable objects, `Grabbable` now automatically creates a `BaseInteractable` component.

For custom interactables:
```gdscript
# Create BaseInteractable as child of your StaticBody3D/RigidBody3D
var interactable = BaseInteractable.new()
add_child(interactable)
interactable.interaction_layers = 1 << 5  # Layer 6

# Connect signals
interactable.selected.connect(_on_selected)
interactable.activated.connect(_on_activated)
```

## Desktop Mouse Interaction

### 1. Add MouseInteractor to player

```gdscript
# In desktop_controller.gd or player script:
var mouse_interactor = MouseInteractor.new()
mouse_interactor.name = "MouseInteractor"
add_child(mouse_interactor)

# Set camera reference
mouse_interactor.set_camera(camera)
```

### 2. Mouse interactor will automatically:
- Raycast from camera through mouse position
- Highlight interactables on hover
- Select on left-click
- Activate on right-click

## Layer Configuration

Make sure collision layers are set correctly:
- Layer 6 (interactable): For all interactable objects
- Interactor collision_mask should include layer 6

In project settings:
```
3d_physics/layer_6="interactable"
```
