# Tools Demo: CSG + Procedural Materials

This demo combines **Constructive Solid Geometry (CSG)** with a variety of **Procedurally Generated Materials**.

## Features

### Procedural Grid
The demo features a common script `procedural_grid.gd` that:
1.  Generates a grid texture at runtime using the `Image` class.
2.  Creates a `StandardMaterial3D` with triplanar mapping.
3.  Applies the material to its parent or child nodes.

### Full Material Showcase
The scene showcases every technique from the procedural materials demo applied to CSG objects:
-   **Noise Patterns**: Grass, Sand, Marble, Ice, and Lava.
-   **Scripting**: The dynamic grid texture.
-   **Shaders**: Glass refraction and transparent effects.

### CSG Operations
The scene demonstrates how procedural materials interact with CSG geometry:
-   **Subtraction**: Cylindrical and spherical holes in boxes.
-   **Triplanar Mapping**: Ensures textures like Grass or Sand align correctly across complex merged shapes.
-   **Real-time Feedback**: Materials are visible directly in the Godot editor.

## How to use
1.  Open `tools_demo.tscn`.
2.  Navigate the 3D viewport to see the different material examples (Grass cylinder, Lava box, Marble cube, etc.).
3.  Adjust variables like `grid_color` or `apply_to_children` on nodes using `procedural_grid.gd`.
