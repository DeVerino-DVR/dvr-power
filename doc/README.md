# TH_POWER - Système de Sorts Magiques

## Description
`dvr_power` est un système de sorts magiques complet pour FiveM avec ESX, incluant un HUD interactif, gestion des cooldowns, système de professeur, et architecture modulaire pour l'enregistrement de sorts externes.

## Fonctionnalités

### 🎯 Système de Sorts
- **HUD Interactif** : Interface utilisateur avec 5 positions de sorts (top, left, center, right, bottom)
- **Gestion des Cooldowns** : Système de cooldowns avec persistance et affichage visuel
- **Assignation de Touches** : Assignation des sorts aux touches 4, 5, 6, 7, 8
- **Système de Professeur** : Interface pour donner/retirer des sorts aux joueurs
- **Sons et Effets** : Sons de confirmation/échec avec anti-spam
- **Persistance** : Sauvegarde des assignations et cooldowns en cache client

### 🏥 Système HP Magique
- **HP Séparé** : Système de points de vie magiques indépendant
- **Gestion de la Mort** : Système de mort avec respawn automatique
- **Barres Visuelles** : Affichage des barres de vie, faim, soif avec effets visuels
- **Régénération** : Système de régénération automatique des HP
- **Dégâts et Soins** : API pour infliger des dégâts et soigner les joueurs

### 🔧 Architecture Modulaire
- **Enregistrement de Modules** : Système pour enregistrer des sorts externes
- **Filtrage par Clés** : Sorts avec propriété `keys` non affichés dans le HUD
- **Callbacks et Exports** : API complète pour l'intégration

## Installation

### Prérequis
- ESX Framework
- ox_lib
- lo_audio
- oxmysql

### Configuration
1. Ajoutez `dvr_power` à votre `server.cfg`
2. Configurez la base de données (voir section Base de Données)
3. Ajustez la configuration dans `config/config.lua`

## Base de Données

```sql
-- Table des sorts des joueurs
CREATE TABLE IF NOT EXISTS `character_spells` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `identifier` varchar(50) NOT NULL,
    `spell_id` varchar(50) NOT NULL,
    `level` tinyint(3) unsigned NOT NULL DEFAULT 0,
    `learned_at` int(11) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_spell` (`identifier`, `spell_id`)
);

-- Table des HP magiques
CREATE TABLE IF NOT EXISTS `character_magic_hp` (
    `identifier` varchar(50) NOT NULL,
    `current_hp` int(11) NOT NULL DEFAULT 100,
    `max_hp` int(11) NOT NULL DEFAULT 100,
    `is_dead` tinyint(1) NOT NULL DEFAULT 0,
    `last_damage_time` int(11) DEFAULT NULL,
    PRIMARY KEY (`identifier`)
);
```

## API - Exports Serveur

### `registerModule(moduleData, source)`
Enregistre un module de sorts externe.

**Paramètres :**
- `moduleData` (table) : Données du module
- `source` (number, optionnel) : ID du joueur qui enregistre (0 pour système)

**Structure moduleData :**
```lua
{
    name = "Nom du Module",
    spells = {
        {
            id = "spell_id",
            name = "Nom du Sort",
            description = "Description",
            color = "white",
            cooldown = 5000,
            type = "attack", -- attack, defense, heal, control
            selfCast = false,
            castTime = 2000,
            sound = "sound_url",
            animation = "animation_name",
            effect = {},
            keys = "L" -- Si défini, le sort ne s'affiche pas dans le HUD
        }
    }
}
```

**Exemple :**
```lua
exports['dvr_power']:registerModule({
    name = "Lumos",
    spells = {
        {
            id = "lumos",
            name = "Lumos",
            description = "Crée une lumière",
            color = "yellow",
            cooldown = 3000,
            type = "utility",
            keys = "L"
        }
    }
})
```

> Astuce : réenregistrer un module avec le même `name` remplace automatiquement l'ancienne version et nettoie les sorts précédemment indexés côté client/serveur.

### `unregisterModule(moduleName, source)`
Désenregistre un module.

**Paramètres :**
- `moduleName` (string) : Nom du module
- `source` (number, optionnel) : ID du joueur

### `getModule(moduleName)`
Récupère les données d'un module.

**Retour :** Table des données du module ou `nil`

### `GetSpellCooldown(spellId)`
Récupère le cooldown d'un sort.

**Retour :** Nombre (millisecondes)

### `GetSpell(targetOrSpellId, spellId)`
Retourne si un joueur connaît un sort et son niveau actuel.

**Paramètres :**
- `targetOrSpellId` (number | string) : ID serveur ou identifier du joueur. Si `spellId` est omis, passez seulement l'ID du sort et l'export utilisera `source` dans un handler serveur.
- `spellId` (string, optionnel) : ID du sort (obligatoire si `targetOrSpellId` est un joueur).

**Retour :** `boolean hasSpell`, `number level`, `string spellName`

**Exemples :**
```lua
-- Dans un événement serveur, utilise automatiquement `source`
local hasSpell, level = exports['dvr_power']:GetSpell('mortalis')

-- Depuis un autre script serveur
local hasSpell, level, name = exports['dvr_power']:GetSpell(targetPlayerId, 'mortalis')
```

> Note : Le même export existe côté client et retourne l'état du joueur local.

### `GetSpellName(spellId)`
Retourne le nom affiché d'un sort (ou son ID s'il n'existe pas).

**Retour :** string

```lua
local displayName = exports['dvr_power']:GetSpellName('mortalis')
```

### `getAllModules()`
Récupère tous les modules enregistrés.

**Retour :** Table des modules

## API - Système HP et Barres

### Exports HP Serveur

#### `HPSystem.DealDamage(source, damage, attackerId, spellId)`
Inflige des dégâts à un joueur.

**Paramètres :**
- `source` (number) : ID du joueur cible
- `damage` (number) : Montant des dégâts
- `attackerId` (number, optionnel) : ID de l'attaquant
- `spellId` (string, optionnel) : ID du sort utilisé

**Retour :** `boolean` - `true` si les dégâts ont été appliqués

**Exemple :**
```lua
-- Dans votre sort d'attaque
local success = HPSystem.DealDamage(targetId, 25, source, "avada_kedavra")
if success then
    print("Dégâts infligés avec succès")
end
```

#### `HPSystem.Heal(source, amount)`
Soigne un joueur.

**Paramètres :**
- `source` (number) : ID du joueur à soigner
- `amount` (number) : Montant de soin

**Retour :** `boolean, number` - Succès et montant réel de soin

**Exemple :**
```lua
-- Dans votre sort de soin
local success, actualHeal = HPSystem.Heal(targetId, 50)
if success then
    print("Soigné de " .. actualHeal .. " HP")
end
```

#### `HPSystem.GetHP(source)`
Récupère les HP d'un joueur.

**Paramètres :**
- `source` (number) : ID du joueur

**Retour :** Table avec `current`, `max`, `isDead`, `lastDamageTime`

**Exemple :**
```lua
local hp = HPSystem.GetHP(playerId)
if hp then
    print("HP actuel: " .. hp.current .. "/" .. hp.max)
    print("Mort: " .. tostring(hp.isDead))
end
```

### Mise à Jour des Barres HUD

#### `HUD.UpdateStats(health, hunger, thirst, magicHp)`
Met à jour toutes les barres du HUD.

**Paramètres :**
- `health` (number, optionnel) : Pourcentage de vie (0-100)
- `hunger` (number, optionnel) : Pourcentage de faim (0-100)
- `thirst` (number, optionnel) : Pourcentage de soif (0-100)
- `magicHp` (number, optionnel) : Pourcentage HP magique (0-100)

**Exemple :**
```lua
-- Mettre à jour toutes les barres
HUD.UpdateStats(85, 60, 40, 100)

-- Mettre à jour seulement la faim
HUD.UpdateStats(nil, 75, nil, nil)
```

#### Messages NUI pour Barres Individuelles

**Santé :**
```lua
SendNUIMessage({
    action = 'updateHealth',
    value = 85 -- Pourcentage 0-100
})
```

**Faim :**
```lua
SendNUIMessage({
    action = 'updateHunger',
    value = 60 -- Pourcentage 0-100
})
```

**Soif :**
```lua
SendNUIMessage({
    action = 'updateThirst',
    value = 40 -- Pourcentage 0-100
})
```

**HP Magique :**
```lua
SendNUIMessage({
    action = 'updateMagicHp',
    value = 100 -- Pourcentage 0-100
})
```

**Potion :**
```lua
SendNUIMessage({
    action = 'updatePotion',
    value = 50 -- Pourcentage 0-100
})
```

### Intégration ESX Status

Le système s'intègre automatiquement avec `esx_status` pour la faim et la soif :

```lua
-- Écouter les changements de statut
AddEventHandler('esx_status:onTick', function(data)
    for i = 1, #data do
        local status = data[i]
        if status.name == 'hunger' then
            HUD.stats.hunger = status.val
        elseif status.name == 'thirst' then
            HUD.stats.thirst = status.val
        end
    end
end)
```

### Commandes HP

#### `/sethp [playerId] [amount]`
Définit les HP d'un joueur (admin uniquement).

**Exemple :**
```
/sethp 1 100
/sethp 2 50
```

#### `/heal [playerId] [amount]`
Soigne un joueur (admin uniquement).

**Exemple :**
```
/heal 1 25
/heal 2 100
```

### Configuration HP

#### `config/hp_config.lua`
```lua
HP_CONFIG = {
    START_HP = 100,                    -- HP de départ
    MAX_HP = 100,                      -- HP maximum
    REGEN_ENABLED = true,              -- Régénération activée
    REGEN_RATE = 1,                    -- HP régénérés par tick
    REGEN_INTERVAL = 5000,             -- Intervalle de régénération (ms)
    REGEN_DELAY_AFTER_DAMAGE = 10000,  -- Délai avant régénération (ms)
    DEATH_RESPAWN_TIME = 30000,        -- Temps de respawn (ms)
    DeathCause = {
        {
            name = "Chute",
            id = {1, 2, 3},
            removeHp = 20
        },
        {
            name = "Explosion",
            id = {4, 5},
            removeHp = 50
        }
    }
}
```

### Exemples d'Intégration HP

#### Sort de Soin
```lua
-- Dans votre sort de soin
local function CastHealSpell(targetId)
    local success, actualHeal = HPSystem.Heal(targetId, 50)
    if success then
        lib.notify({
            title = "Soin",
            description = "Soigné de " .. actualHeal .. " HP",
            type = "success"
        })
    end
end
```

#### Sort d'Attaque
```lua
-- Dans votre sort d'attaque
local function CastAttackSpell(targetId, damage)
    local success = HPSystem.DealDamage(targetId, damage, source, "avada_kedavra")
    if success then
        lib.notify({
            title = "Attaque",
            description = "Dégâts infligés: " .. damage,
            type = "info"
        })
    end
end
```

#### Mise à Jour Personnalisée des Barres
```lua
-- Créer un système de potions personnalisé
local function UsePotion()
    local currentPotion = GetResourceKvpInt('dvr_power:potion_amount') or 0
    if currentPotion > 0 then
        currentPotion = currentPotion - 1
        SetResourceKvpInt('dvr_power:potion_amount', currentPotion)
        
        -- Mettre à jour la barre de potion
        SendNUIMessage({
            action = 'updatePotion',
            value = (currentPotion / 10) * 100 -- 10 potions max
        })
        
        -- Soigner le joueur
        HPSystem.Heal(GetPlayerServerId(PlayerId()), 25)
    end
end
```

## API - Callbacks

### `dvr_power:registerModuleServer`
Callback pour enregistrer un module depuis le client.

**Utilisation :**
```lua
local success = lib.callback.await('dvr_power:registerModuleServer', false, moduleData)
```

### `dvr_power:professorGetPlayers`
Récupère la liste des joueurs pour le système professeur.

**Retour :** Table des joueurs avec `id`, `name`, `identifier`

### `dvr_power:getPlayerSpells`
Récupère les sorts d'un joueur.

**Retour :** Table des IDs de sorts

## API - Événements

### Événements Serveur

#### `dvr_power:castSpell`
Lance un sort.

**Paramètres :**
- `spellId` (string) : ID du sort
- `targetCoords` (vector3) : Coordonnées de la cible
- `targetServerId` (number) : ID serveur de la cible

#### `dvr_power:playSpellSound`
Joue le son d'un sort.

**Paramètres :**
- `spellId` (string) : ID du sort
- `coords` (vector3) : Coordonnées où jouer le son

#### `dvr_power:requestRemoveLight`
Demande la suppression d'une lumière.

**Paramètres :**
- `lightId` (string) : ID de la lumière

### Événements Client

#### `dvr_power:registerModule`
Enregistre un module côté client.

**Paramètres :**
- `moduleData` (table) : Données du module

#### `dvr_power:loadSpells`
Charge les sorts d'un joueur.

**Paramètres :**
- `spells` (table) : Liste des IDs de sorts

#### `dvr_power:spellCast`
Événement de lancement de sort.

**Paramètres :**
- `source` (number) : ID du joueur qui lance
- `spellId` (string) : ID du sort
- `targetCoords` (vector3) : Coordonnées de la cible

#### `dvr_power:spellRemoved`
Événement de suppression de sort.

**Paramètres :**
- `spellId` (string) : ID du sort supprimé

#### `dvr_power:updateHP`
Met à jour les HP magiques.

**Paramètres :**
- `current` (number) : HP actuels
- `max` (number) : HP maximum
- `deathType` (string) : Type de mort
- `damageAmount` (number) : Montant des dégâts

#### `dvr_power:playerDied`
Événement de mort du joueur.

## State Bags

### `LocalPlayer.state.invOpen`
État d'ouverture de l'inventaire (boolean).

**Utilisation :**
```lua
local invOpen = LocalPlayer.state.invOpen
```

### `LocalPlayer.state.magicHp`
HP magique actuel du joueur (number).

**Utilisation :**
```lua
local magicHp = LocalPlayer.state.magicHp or 100
```

## Cache Client (KVP)

### `dvr_power:spell_key_assignments`
Sauvegarde des assignations de sorts aux touches.

**Format :** JSON string
```json
{
    "spell_id": "position",
    "avada_kedavra": "center",
    "basic": "bottom"
}
```

### `dvr_power:active_cooldowns`
Sauvegarde des cooldowns actifs.

**Format :** JSON string
```json
{
    "spell_id": "end_timestamp",
    "avada_kedavra": "1760905867"
}
```

### `dvr_power:last_active_spell`
Sort actuellement sélectionné.

**Format :** String
```
"avada_kedavra"
```

## Commandes

### `/hud`
Bascule l'affichage du HUD.

### `/reloadspells`
Recharge les sorts du joueur.

### `/professor`
Ouvre le menu professeur (nécessite permission).

## Configuration

### `config/config.lua`
```lua
Config = {
    WandWeapon = 'WEAPON_MAGIC_WAND', -- Arme baguette magique
    SpellColors = {
        white = {r = 255, g = 255, b = 255},
        red = {r = 255, g = 0, b = 0},
        -- ...
    }
}
```

### `config/hp_config.lua`
```lua
HP_CONFIG = {
    START_HP = 100,        -- HP de départ
    MAX_HP = 100,          -- HP maximum
    DEATH_RESPAWN_TIME = 10000, -- Temps de respawn (ms)
    DeathCause = {
        -- Causes de mort et dégâts
    }
}
```

## Intégration Exemple

### Créer un Sort Externe
```lua
-- Dans votre ressource
local function RegisterMySpell()
    exports['dvr_power']:registerModule({
        name = "Mon Module",
        spells = {
            {
                id = "mon_sort",
                name = "Mon Sort",
                description = "Description de mon sort",
                color = "blue",
                cooldown = 5000,
                type = "attack",
                selfCast = false,
                castTime = 2000,
                sound = "https://example.com/sound.mp3",
                animation = "cast_spell",
                effect = {
                    particle = "spell_effect",
                    duration = 3000
                }
            }
        }
    })
end

-- Enregistrer au démarrage
CreateThread(function()
    Wait(5000) -- Attendre que dvr_power soit prêt
    RegisterMySpell()
end)
```

### Sort avec Touche Directe
```lua
-- Sort qui ne s'affiche pas dans le HUD mais a une touche directe
exports['dvr_power']:registerModule({
    name = "Sort Secret",
    spells = {
        {
            id = "sort_secret",
            name = "Sort Secret",
            description = "Sort avec touche directe",
            keys = "L", -- Touche L directe, ne s'affiche pas dans le HUD
            cooldown = 3000,
            type = "utility"
        }
    }
})
```

## Dépannage

### Problèmes Courants

1. **HUD ne s'affiche pas**
   - Vérifiez que le joueur a une baguette magique
   - Vérifiez les permissions ESX

2. **Sorts ne se lancent pas**
   - Vérifiez que le sort est enregistré
   - Vérifiez les cooldowns
   - Vérifiez les sons (lo_audio requis)

3. **Cooldowns ne persistent pas**
   - Vérifiez les permissions de cache client
   - Vérifiez la configuration KVP

### Logs de Debug
Activez les logs dans `client/main.lua` et `server/main.lua` pour diagnostiquer les problèmes.

## Support

Pour toute question ou problème, consultez les logs du serveur et du client, et vérifiez la configuration ESX et des dépendances.
