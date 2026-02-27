# th_power - Spell System for FiveM

A complete magic spell system for FiveM, including HUD, spell management, leveling, magic HP, professor interface, and modular spell architecture.

> Originally developed for the VLight RP event.

## Important Notice

This script is **complex**. It was specifically designed for a custom FiveM server environment. If you are not experienced with FiveM development or adapting advanced systems, it will be very difficult to install or modify correctly.

**No support will be provided. There will be no help, assistance, or custom adaptation. The system is given as-is.**

If you use it, you must know what you are doing.

## Credits

This script is distributed for free. Credits must remain attributed to:
- **VLight** (original author)
- **@dxqson**
- **@dolyyy**
- **@lu_value**

Please respect the work that went into this project.

## Features

- Diamond-shaped spell HUD with 5 slots (configurable hotkeys)
- 5 customizable spell sets per player
- Spell leveling system (0-5) with progression
- Magic HP system (separate from physical health)
- Professor/teacher interface for managing student spells
- Modular architecture for spell plugins
- Discord webhook logging
- Wand weapon system with trail effects
- NUI-based spell selector UI
- Database persistence (MySQL)

## Requirements

You need to install and configure the following dependencies:

| Dependency | Description | Link |
|---|---|---|
| **ox_lib** | Shared utility library | [GitHub](https://github.com/overextended/ox_lib) |
| **oxmysql** | MySQL database adapter | [GitHub](https://github.com/overextended/oxmysql) |
| **es_extended** | ESX Framework (or adapt to your framework) | [GitHub](https://github.com/esx-framework/esx_core) |
| **Audio system** | You need your own audio resource | See below |

### Audio System

The original audio system (`lo_audio`) has been removed. All audio calls are commented out with `-- REPLACE WITH YOUR SOUND SYSTEM`. You need to replace these with your own audio resource (e.g. `xsound`, `interact-sound`, or any other FiveM audio resource).

Search for `REPLACE WITH YOUR SOUND SYSTEM` in the code to find all locations that need audio integration.

### Sound URLs

All sound and video URLs have been replaced with `YOUR_SOUND_URL_HERE` / `YOUR_VIDEO_URL_HERE`. You need to host your own audio files and replace these placeholders.

## Installation

1. Install all required dependencies listed above
2. Uncomment the dependency imports in `fxmanifest.lua`:
   ```lua
   shared_scripts {
       '@ox_lib/init.lua',
       '@es_extended/imports.lua',
       'config/config.lua',
       'config/logs.lua',
   }

   server_scripts {
       '@oxmysql/lib/MySQL.lua',
       -- ...
   }
   ```
3. Configure `config/config.lua`:
   - Set your sound URLs
   - Configure damage immunity list
   - Adjust spell settings as needed
4. Configure `config/logs.lua`:
   - Set your Discord webhook URLs
   - Set your server name
5. Add `th_power` to your server resources and ensure it starts before any spell modules
6. Install spell modules from [th-power-spells](https://github.com/YOUR_USERNAME/th-power-spells)

## Spell Modules

Spell modules are separate resources that register with th_power. See the [th-power-spells](https://github.com/YOUR_USERNAME/th-power-spells) repository for all available spells.

## Structure

```
th_power/
├── client/           # Client-side scripts
│   ├── main.lua      # Core spell system
│   ├── hud.lua       # HUD management
│   ├── hp_system.lua # Client HP management
│   └── ...
├── server/           # Server-side scripts
│   ├── main.lua      # Core server logic
│   ├── hp_system.lua # Magic HP system
│   ├── damage_system.lua
│   └── ...
├── config/           # Configuration
│   ├── config.lua    # Main config
│   └── logs.lua      # Discord webhook config
├── html/             # NUI interface
├── stream/           # Streaming assets (particles)
└── fxmanifest.lua
```

## Exports

### Server Exports
- `registerModule(moduleData, source)` - Register a spell module
- `GetSpell(target, spellId)` - Check if player has spell
- `DealDamage(source, damage, attackerId, spellId)` - Inflict magic damage
- `Heal(source, amount)` - Heal a player
- `ApplySpellDamage(source, damage, attackerId, spellId)` - Apply spell damage
- `ApplyAreaDamage(source, damage, attackerId, spellId)` - Area damage
- `LogSpellCast(source, spellId, targetId)` - Log spell usage

### Client Exports
- `GetSpell(spellId)` - Get local player spell data
- `getPlayerSpells()` - Get all player spells
- `getSelectedSpell()` - Get currently selected spell
- `registerModule(moduleData)` - Register spell module client-side
- `ToggleHUD(visible)` - Show/hide HUD

## License

Free to use. Credits to VLight, @dxqson, @dolyyy, and @lu_value are **mandatory**.
