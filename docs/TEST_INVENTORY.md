# Manual Test Instructions for Inventory System

## Prerequisites
1. Make sure Godot editor is closed
2. Reopen the project in Godot to reload the autoloads

## Test Plan

### Test 1: Verify Autoloads
1. In Godot, go to **Project > Project Settings > Autoload**
2. Verify these autoloads exist:
   - `SaveManager` → `res://src/systems/save_manager.gd`
   - `InventoryManager` → `res://src/systems/inventory_manager.gd`
   - `NetworkManager` → `res://multiplayer/network_manager.gd`

### Test 2: Run MainScene
1. Run `res://src/levels/MainScene.tscn`
2. You should see the Inventory UI panel in the 3D world at position (1.5, 1.5, -2)
3. The panel should display:
   - "INVENTORY" title
   - Gold: 0
   - Gems: 0
   - Tokens: 0
   - Empty inventory grid

### Test 3: Test Debug Keys
With the game running, press these keys:

- **Press 1**: Should add 100 gold
  - Check console for: "Debug: Added 100 gold"
  - Check console for: "SaveManager: Added 100 gold"
  - Look at inventory panel - Gold should show 100

- **Press 2**: Should add 10 gems
  - Check console for messages
  - Panel should update to show 10 gems

- **Press 3**: Should add 5 tokens
  - Panel should show 5 tokens

- **Press 4**: Should add 1 sword
  - A new slot should appear in the inventory grid
  - Shows "sword" and "x1"

- **Press 5**: Add 3 potions (multiple times to test stacking)
  - First press: adds "potion x3"
  - Second press: should update to "potion x6"

- **Press 6**: Add 10 gem fragments
  - Should see "gem_fragment x10"

- **Press 0**: Reset all data
  - All currency should go back to 0
  - All inventory slots should disappear

### Test 4: Test Persistence
1. Add some currency with keys 1, 2, 3
2. Add some items with keys 4, 5, 6
3. Check the saved file exists at: `user://save_data.json`
4. Close the game
5. Run MainScene again
6. **Verify**: All currency and items should be restored

### Test 5: Test Live Updates
1. Open the console/output panel in Godot
2. Run the game
3. Press number keys and watch:
   - Console messages confirm actions
   - Inventory panel updates immediately (no need to toggle/refresh)

## Common Issues

### Issue: "InventoryManager not declared" errors
**Solution**: Close and reopen the Godot project to reload autoloads

### Issue: Inventory panel not visible
**Solution**: 
1. Check the 3D scene - panel is at (1.5, 1.5, -2)
2. Move camera to see it
3. Check that InventoryUIViewport3D node exists in MainScene

### Issue: No response to debug keys
**Solution**:
1. Make sure MainScene is running (not just the scene editor)
2. Check that InventoryDebug node exists in MainScene
3. Check console for errors

### Issue: Panel shows but doesn't update
**Solution**: Check console for errors about missing autoloads

## Expected Console Output

When working correctly, you should see:
```
SaveManager: Initialized, save file: user://save_data.json
SaveManager: Loaded save data: [whatever was saved]
Debug: Added 100 gold
SaveManager: Added 100 gold. New total: 100
InventoryManager: Added 1 of sword
SaveManager: Game state saved to user://save_data.json
```

## Files Changed

The following files were created/modified:
- `src/systems/save_manager.gd` - Added currency and inventory persistence
- `src/systems/inventory_manager.gd` - NEW - Manages inventory logic
- `src/resources/inventory_item.gd` - NEW - Resource for items
- `src/ui/InventoryUI.gd` - NEW - 2D UI panel
- `src/ui/InventoryUI.tscn` - NEW - UI scene
- `src/ui/InventoryUIViewport3D.tscn` - NEW - 3D viewport wrapper
- `src/ui/inventory_ui_viewport_3d.gd` - NEW - Viewport interaction
- `src/debug/inventory_debug.gd` - NEW - Debug key handler
- `project.godot` - Added InventoryManager autoload
- `src/levels/MainScene.tscn` - Added InventoryUIViewport3D and debug node
