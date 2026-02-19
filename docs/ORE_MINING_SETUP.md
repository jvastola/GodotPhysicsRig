# Ore Mining System Setup

## Overview
The ore mining system allows players to break ore deposits using:
- Mining tools (sticks/pickaxes) - Required for iron ore
- Bare hands (punching) - Works for gold ore only

## Features
- Iron ore plays `ironhit.ogg` sound effect on successful hit
- Failed hits (without tool) play `hitwood.ogg` sound effect
- Gold ore has a distinctive golden metallic appearance with glow
- Different ore types give different currencies
- Iron ore requires a tool to break
- Gold ore can be broken with bare hands
- Ore respawns after 30 seconds
- Ore chunks have physics (gravity, bouncing)
- Chunks are auto-collected when player walks over them

## Ore Types & Currency Rewards

### Iron Ore
- **Currency**: Tokens (yellow) - 5 to 15 per deposit
- **Sound**: ironhit.ogg (successful hit), hitwood.ogg (failed hit without tool)
- **Health**: 100 (default)
- **Requires Tool**: YES - Cannot be broken with bare hands
- **Tool Feedback**: Plays hitwood.ogg sound when hit without tool
- **Appearance**: Brownish gray, low metallic

### Gold Ore
- **Currency**: Gold - 15 to 30 per deposit
- **Sound**: ironhit.ogg
- **Health**: 100 (default)
- **Requires Tool**: NO - Can be broken with bare hands or tools
- **Appearance**: Bright gold color with metallic shine and slight glow

### Copper Ore
- **Currency**: Tokens (yellow) - 2 to 8 per deposit
- **Sound**: ironhit.ogg (successful hit), hitwood.ogg (failed hit without tool)
- **Health**: 100 (default)
- **Requires Tool**: YES (default)
- **Appearance**: Copper/orange color with metallic finish

## Setting Up Ore Deposits in Scene

### Method 1: Using Existing OreDeposit Scene
1. Add an OreDeposit node to your scene
2. Set the `ore_type` property to "iron", "gold", or "copper"
3. The `requires_tool` property is automatically set based on ore type:
   - Iron: requires_tool = true
   - Gold: requires_tool = false
   - Copper: requires_tool = true (default)
4. To change the material:
   - Make the OreDeposit node editable (right-click > Make Local or Editable Children)
   - Select the MeshInstance3D child
   - In the Inspector, set Material Override to your custom material
   - For gold ore, you can use the StandardMaterial3D_gold from OreDeposit.tscn
5. Adjust health, loot amounts, and respawn time as needed

### Method 2: Creating from Scratch
1. Create a StaticBody3D node
2. Attach the `OreDeposit.gd` script
3. Add a MeshInstance3D child with your ore model
4. Set the material on the MeshInstance3D
5. Add a CollisionShape3D child
6. Configure properties:
   - `ore_type`: "iron", "gold", or "copper"
   - `max_health`: 100 (default)
   - `loot_amount_min`: 1
   - `loot_amount_max`: 3
   - `respawn_time`: 30.0 seconds
   - `hand_damage_multiplier`: 3.0
   - `min_hand_velocity`: 0.8
   - `requires_tool`: Auto-set based on ore_type (or manually override)

### Available Materials in OreDeposit.tscn
- `StandardMaterial3D_iron`: Brownish gray, low metallic (default)
- `StandardMaterial3D_gold`: Bright gold with metallic shine and glow

## Hand Mining Settings

Players can punch ore without holding a tool:
- **Minimum velocity**: 0.8 m/s (configurable via `min_hand_velocity`)
- **Damage multiplier**: 3.0 (configurable via `hand_damage_multiplier`)
- **Cooldown**: 0.2 seconds between hits

Example: A punch at 2 m/s velocity deals 6 damage (2 * 3.0)

## Tool Mining Settings

Mining tools (like sticks) have their own settings:
- **Damage multiplier**: 5.0 (in MiningTool.gd)
- **Minimum velocity**: 0.5 m/s
- **Cooldown**: 0.2 seconds

## Ore Chunk Physics

When ore is broken, it drops physical chunks:
- RigidBody3D with gravity enabled
- Scatter with random impulses
- Bounce and roll realistically
- Magnet effect pulls them toward player
- Auto-pickup on contact
- Despawn after 30 seconds if not collected

## Currency Display

The HUD automatically updates when currency is collected:
- **Gold**: Yellow circular icon
- **Gems**: Blue diamond icon
- **Tokens**: Purple circular icon (yellow currency)

## Testing

To test the system:
1. Add iron and gold ore deposits to your scene
2. Enter VR mode
3. Try punching iron ore with your hand - it should play hitwood.ogg and not break
4. Grab a mining tool (stick) and hit the iron ore - it should play ironhit.ogg and break
5. Punch the gold ore with your hand - it should break and give gold currency
6. Notice the gold ore has a shiny golden appearance
7. Watch the HUD update with currency
8. Collect the dropped ore chunks
9. Wait 30 seconds to see ore respawn

## Troubleshooting

**Iron ore not taking damage from tools:**
- Make sure the tool has the MiningTool.gd script attached
- Verify the tool is in the "mining_tool" group
- Check that tool velocity is above min_damage_velocity (0.5 m/s)

**Gold ore not taking damage from hands:**
- Make sure the ore's collision_layer is set to 1
- Check that physics_hand is in the "physics_hand" group
- Verify hand velocity is above min_hand_velocity (0.8 m/s)
- Ensure ore_type is set to "gold"

**Iron ore breaking with bare hands:**
- Check that ore_type is set to "iron"
- Verify requires_tool is set to true
- The ore should play hitwood.ogg sound when hit without a tool

**No sound playing:**
- Verify `assets/audio/ironhit.ogg` exists for successful hits
- Verify `assets/audio/hitwood.ogg` exists for failed hits
- Check audio player max_distance (default: 25.0)

**Currency not updating:**
- Ensure InventoryManager autoload is enabled
- Check that ore_type matches "iron", "gold", or "copper"
- Verify HUD is connected to InventoryManager signals
