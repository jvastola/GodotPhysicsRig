# Mining System

A simple mining mechanic for VR that allows players to mine ore deposits using a mining tool (stick).

## Components

### MiningTool (src/objects/grabbables/MiningTool.gd)
A grabbable tool that can mine ore deposits when swung at them.

**Features:**
- Extends the base Grabbable class
- Detects mining hits based on swing velocity
- Has configurable mining damage, range, and cooldown
- Uses physics-based collision detection

**Exported Properties:**
- `mining_damage` (float): Damage dealt per hit (default: 10.0)
- `mining_range` (float): Detection range for ore deposits (default: 1.5)
- `hit_cooldown` (float): Time between hits in seconds (default: 0.3)

**How it works:**
1. Player grabs the mining tool
2. Swings it with velocity > 2.0 m/s
3. Tool checks for ore deposits within range using physics queries
4. Applies damage to any ore deposit hit

### OreDeposit (src/objects/OreDeposit.gd)
A static body that can be mined for resources.

**Features:**
- Takes damage from mining tools
- Visual feedback when hit (flash effect + particles)
- Drops loot items when depleted
- Configurable ore type and health

**Exported Properties:**
- `ore_type` (String): Type of ore (iron, gold, copper, etc.)
- `max_health` (float): Total health before depletion (default: 100.0)
- `loot_amount_min` (int): Minimum loot dropped (default: 1)
- `loot_amount_max` (int): Maximum loot dropped (default: 3)
- `drop_loot` (bool): Whether to drop physical loot or add to inventory (default: true)

**Signals:**
- `ore_depleted(ore_type: String, amount: int)`: Emitted when ore is fully mined
- `ore_damaged(health_remaining: float)`: Emitted when ore takes damage

## Usage

### In the Main Scene
The stick in the main scene has been converted to a MiningTool. Three ore deposits have been added nearby for testing.

**Location:** Around position (2, 0.5, -36) in the main scene

### Creating New Ore Deposits
1. Instance `OreDeposit.tscn` in your scene
2. Configure the ore type and health in the inspector
3. Position it in the world
4. The ore will automatically be on collision layer 11 for mining tool detection

### Customizing Ore Types
Edit the `_create_loot_item()` method in `OreDeposit.gd` to add new ore types with custom colors:

```gdscript
match ore_type:
    "iron":
        mat.albedo_color = Color(0.7, 0.7, 0.7)
        mat.metallic = 0.8
    "your_ore":
        mat.albedo_color = Color(1.0, 0.0, 1.0)
        mat.metallic = 0.5
```

## Future Enhancements

Possible improvements:
- Inventory system to collect mined resources
- Different tool types (pickaxe, drill, etc.)
- Ore respawning system
- Mining skill progression
- Sound effects and better particle effects
- Tool durability system
- Different ore hardness requiring better tools
