# Mining System - Quick Start

## What Was Added

1. **MiningTool** - A grabbable stick that damages ore on collision
   - Location: `src/objects/grabbables/MiningTool.gd` and `.tscn`
   - Uses physics collision detection with the hand when grabbed

2. **OreDeposit** - Mineable ore blocks that drop loot and respawn
   - Location: `src/objects/OreDeposit.gd` and `.tscn`
   - Shows health, shakes when hit, respawns after 30 seconds
   - Drops OreChunk items when depleted

3. **OreChunk** - Auto-pickup loot items
   - Location: `src/objects/OreChunk.gd`
   - Automatically collected when player touches them
   - Adds to inventory with visual feedback
   - Has magnet effect to attract to nearby player

4. **InventoryManager** - Simple inventory system
   - Location: `src/systems/inventory_manager.gd`
   - Tracks collected resources
   - Autoloaded singleton

## How to Use

1. **Start the game** and go to the main scene
2. **Find the stick** at position (2, 0, -35.5)
3. **Grab the stick** with your VR controller
4. **Swing and hit** the nearby ore cubes
   - Damage is based on impact velocity
5. **Watch** as the ore takes damage and breaks
6. **Walk over** the dropped ore chunks to collect them
   - They automatically add to your inventory
   - Collection particles play
7. **Wait 30 seconds** for the ore to respawn

## How It Works

### Collision-Based Mining
- The stick detects collisions from the physics hand when grabbed
- **Damage = Impact Velocity × Damage Multiplier (5.0)**
- Minimum velocity of 0.5 m/s required
- Faster swings = more damage!

### Loot System
- Ore drops 1-3 OreChunk items when depleted
- Chunks are Area3D nodes that detect player touch
- **Auto-pickup**: Walk over chunks to collect them
- **Magnet effect**: Chunks move toward nearby player (1.5m range)
- **Lifetime**: Chunks despawn after 30 seconds if not collected
- **Visual feedback**: Collection particles and console messages

### Inventory System
- InventoryManager tracks all collected resources
- Console prints: "Collected X iron (Total: Y)"
- Inventory persists during gameplay
- Access via `InventoryManager.instance.get_item_count("iron")`

### Respawn System
- Ore deposits hide when depleted (not destroyed)
- After 30 seconds, ore respawns with full health
- Respawn has green particle effect
- Collision re-enabled on respawn

### Visual Feedback
- **White flash** on ore when damaged
- **Shake effect** on ore when hit
- **Health label** shows remaining ore health
- **Particle effects** on impact
- **Green particles** on respawn
- **Collection burst** when picking up chunks

## Customization

### Mining Tool Settings
Select the stick in the scene tree:
- `damage_multiplier`: Damage per m/s (default: 5.0)
- `min_damage_velocity`: Minimum velocity (default: 0.5)
- `hit_cooldown`: Time between hits (default: 0.2)

### Ore Deposit Settings
Select an ore deposit:
- `max_health`: Total health (default: 100.0)
- `loot_amount_min/max`: Loot dropped (default: 1-3)
- `respawn_time`: Seconds to respawn (default: 30.0)
- `ore_type`: "iron", "gold", "copper"

### Ore Chunk Settings
- `lifetime`: Seconds before despawn (default: 30.0)
- `magnet_range`: Attraction range (default: 1.5)

## Troubleshooting

### Tool not damaging ore?
- Swing fast enough (> 0.5 m/s)
- Check console for "Hit ore with velocity..." messages
- Ensure ore is on collision layer 1

### Chunks not collecting?
- Make sure player body is on collision layer 1
- Check that player is in "player_body" group
- Look for "Collected" messages in console

### Ore not respawning?
- Wait full 30 seconds
- Check console for "Respawning" message
- Ore should reappear with green particles

## Console Messages

Watch for these debug messages:
- `MiningTool: Hit ore with velocity X dealing Y damage`
- `OreDeposit: Depleted! Dropping X iron`
- `OreChunk: Collected iron x1`
- `InventoryManager: Collected 1 iron (Total: X)`
- `OreDeposit: Respawning iron`

## Testing Tips

- Swing harder for more damage!
- Walk over chunks immediately to test auto-pickup
- Watch the magnet effect pull chunks toward you
- Wait for respawn to see the green particle effect
- Check console for inventory totals
