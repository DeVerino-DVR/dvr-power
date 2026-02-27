# Damage System

Système centralisé de gestion des dégâts pour tous les sorts avec **protection automatique contre les explosions natives**.

## 🎯 Pourquoi ce système existe ?

Les explosions natives de GTA V (`AddExplosion`) **ignorent** le paramètre de dégâts et font toujours leurs propres dégâts (~700+). Ce système résout ce problème en :

1. **Protégeant temporairement** les joueurs (invincibilité)
2. **Appliquant les dégâts personnalisés** après la protection
3. **Gardant les effets visuels** intacts

## ✅ Fonctionnalités

- 🛡️ Protection automatique contre les explosions natives
- 🎯 Dégâts personnalisés par niveau de sort
- 💥 **Ragdoll forcé** : Les joueurs sont projetés par les explosions (configurable)
- 🔒 Vérification automatique du bouclier Prothea
- 👤 Le lanceur ne se blesse jamais lui-même
- 📊 Logs de debug optionnels
- ♻️ Entièrement réutilisable pour tout nouveau sort

---

## 📖 Utilisation

### Fonction principale : `ApplySpellDamage`

```lua
exports['th_power']:ApplySpellDamage(
    coords,             -- vector3: Centre de la zone
    spellLevel,         -- number: Niveau du sort (1-5)
    damagePerLevel,     -- number: Dégâts par niveau (50 = niveau 1 fait 50, niveau 2 fait 100)
    radius,             -- number: Rayon en mètres
    sourceId,           -- number: Server ID du lanceur
    spellName,          -- string (optionnel): Nom pour les logs
    protectionDuration, -- number (optionnel): Durée de protection en ms (défaut: 800)
    options             -- table (optionnel): Options avancées (voir ci-dessous)
)
```

### Options avancées

```lua
options = {
    ragdollDuration = 2000,  -- Durée du ragdoll en ms (0 = désactivé, nil = auto basé sur niveau)
    ragdollForce = 1.5       -- Multiplicateur de force du ragdoll (défaut: 1.0)
}
```

**Note sur le ragdoll :** Par défaut, le ragdoll est activé automatiquement avec une durée basée sur le niveau du sort (1.8s à 3s). La force est modulée par la distance à l'explosion (plus proche = plus fort).

### ⚠️ IMPORTANT : Ordre d'exécution

Le sort doit appeler le serveur **AVANT** l'explosion pour que la protection fonctionne :

```lua
-- ✅ BON : Serveur d'abord, puis explosion
if isLocalCaster then
    TriggerServerEvent('mon_sort:applyDamage', coords, level)
end
Wait(50)  -- Laisser le temps au serveur de protéger les joueurs
AddExplosion(coords.x, coords.y, coords.z, 2, 0.1, true, false, 0.3)

-- ❌ MAUVAIS : Explosion d'abord (les dégâts natifs s'appliquent)
AddExplosion(coords.x, coords.y, coords.z, 2, 0.1, true, false, 0.3)
TriggerServerEvent('mon_sort:applyDamage', coords, level)
```

---

## 📝 Exemple complet

### Config du sort (`config.lua`)

```lua
Config.Damage = {
    perLevel = 50,      -- 50 dégâts par niveau
    radius = 5.0        -- Rayon de 5 mètres
}
```

### Côté serveur (`server/main.lua`)

```lua
RegisterNetEvent('mon_sort:applyDamage', function(coords, spellLevel)
    local _source = source
    
    -- Exemple basique (ragdoll automatique)
    exports['th_power']:ApplySpellDamage(
        coords,
        spellLevel,
        Config.Damage.perLevel,  -- 50 dégâts par niveau
        Config.Damage.radius,    -- 5.0m de rayon
        _source,
        'MonSort'
    )
    
    -- Exemple avec options personnalisées
    exports['th_power']:ApplySpellDamage(
        coords,
        spellLevel,
        Config.Damage.perLevel,
        Config.Damage.radius,
        _source,
        'MonSort',
        800,  -- Protection 800ms
        {
            ragdollDuration = 3000,  -- Ragdoll 3 secondes
            ragdollForce = 2.0       -- Force x2
        }
    )
    
    -- Exemple sans ragdoll (sort subtil)
    exports['th_power']:ApplySpellDamage(
        coords,
        spellLevel,
        Config.Damage.perLevel,
        Config.Damage.radius,
        _source,
        'MonSort',
        800,
        { ragdollDuration = 0 }  -- Pas de ragdoll
    )
end)
```

### Côté client (`client/main.lua`)

```lua
-- Quand le projectile atteint sa cible
local coords = GetEntityCoords(projectile)
local level = data.spellLevel or 1

-- 1. D'abord envoyer au serveur (protection des joueurs)
if isLocalCaster then
    TriggerServerEvent('mon_sort:applyDamage', coords, level)
end

-- 2. Attendre que le serveur protège les joueurs
Wait(50)

-- 3. Puis faire l'explosion (visuels seulement maintenant)
AddExplosion(coords.x, coords.y, coords.z, 2, 0.1, true, false, 0.3)
```

---

## 📊 Tableau des dégâts

Avec `perLevel = 50` :

| Niveau | Dégâts | Sur 200 HP | Sur 5200 HP |
|--------|--------|------------|-------------|
| 1 | 50 | 25% | ~1% |
| 2 | 100 | 50% | ~2% |
| 3 | 150 | 75% | ~3% |
| 4 | 200 | 100% | ~4% |
| 5 | 250 | 125% | ~5% |

---

## 🔧 Fonctions additionnelles

### `ApplyAreaDamage` (sans protection)

Pour les sorts qui n'utilisent pas d'explosions natives :

```lua
exports['th_power']:ApplyAreaDamage(
    coords,      -- vector3
    damage,      -- number: Dégâts fixes
    radius,      -- number
    sourceId,    -- number
    spellName    -- string (optionnel)
)
```

### `GetPlayersInRadius`

```lua
local players = exports['th_power']:GetPlayersInRadius(coords, radius, excludeSourceId)
-- Retourne: { {playerId, ped, distance}, ... }
```

### `HasProtheaShield`

```lua
local hasShield = exports['th_power']:HasProtheaShield(playerId)
-- Retourne: boolean
```

---

## 🔄 Comment ça marche

```
┌─────────────────────────────────────────────────────────────┐
│  CLIENT (Lanceur du sort)                                    │
│  1. TriggerServerEvent('sort:applyDamage', coords, level)   │
│  2. Wait(50)                                                 │
│  3. AddExplosion(...)  -- Visuels                           │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  SERVER                                                      │
│  1. Trouve tous les joueurs dans le rayon                   │
│  2. Vérifie le bouclier Prothea                             │
│  3. Calcule la force du ragdoll selon la distance           │
│  4. Envoie 'th_power:protectFromExplosion' aux joueurs      │
│     (avec coords explosion + options ragdoll)               │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  CLIENT (Joueurs touchés)                                    │
│  1. Reçoit l'événement de protection                        │
│  2. Sauvegarde la santé et restaure à chaque frame          │
│  3. Déclenche le ragdoll forcé (SetPedToRagdollWithFall)    │
│  4. Le joueur tombe avec direction depuis l'explosion       │
│  5. Après protection: applique les dégâts personnalisés     │
└─────────────────────────────────────────────────────────────┘
```

**Important :** Le système n'utilise plus `SetEntityInvincible` qui bloquait le ragdoll. À la place, il restaure la santé à chaque frame pendant la protection, permettant au joueur d'être projeté par l'explosion tout en conservant ses HP.

---

## 📋 Sorts utilisant ce système

- ✅ `th_ignifera` - Sort d'explosion de feu
- ✅ `th_thunder` - Sort de foudre

---

## 📝 Signification des logs

### Messages serveur

| Message | Signification |
|---------|---------------|
| `lance un sort niveau X` | Un joueur a lancé un sort, affiche le niveau et les dégâts |
| `X joueur(s) détecté(s)` | Nombre de joueurs dans le rayon de dégâts |
| `Entre en combat` | Un joueur va recevoir des dégâts (protection activée) |
| `Bouclier Prothea actif` | Le joueur a un bouclier, les dégâts sont bloqués |
| `X dégâts seront appliqués` | Dégâts qui seront infligés après la protection |

### Messages client

| Message | Signification |
|---------|---------------|
| `Protection activée` | Le joueur est maintenant invincible temporairement |
| `HP actuel: X / Y` | Points de vie actuels et maximum |
| `Dégâts à appliquer: X` | Dégâts qui seront appliqués après la protection |
| `Dégâts appliqués` | Les dégâts personnalisés ont été appliqués |
| `HP restant: X / Y (Z%)` | Points de vie restants après les dégâts |
| `Vous êtes tombé au combat!` | Le joueur est mort (HP = 0) |

---

## 🐛 Debug et Logs

### Logs automatiques

Le système affiche automatiquement des logs détaillés dans la console serveur et client :

#### Côté Serveur

```
[th_power:DamageSystem] [Ignifera] Joueur123 lance un sort niveau 3 (dégâts: 150, rayon: 5.0m)
[th_power:DamageSystem] [Ignifera] 2 joueur(s) détecté(s) dans le rayon
[th_power:DamageSystem] [Ignifera] Joueur456 (ID: 2) - Entre en combat, 150 dégâts seront appliqués (distance: 3.21m, HP actuel: 5200)
[th_power:DamageSystem] [Ignifera] Joueur789 (ID: 3) - Bouclier Prothea actif, dégâts bloqués (distance: 4.50m)
```

#### Côté Client (joueur touché)

```
[th_power:SpellDamage] Protection activée - Protection contre l'explosion pendant 500ms
[th_power:SpellDamage] HP actuel: 5200 / 5200 - Dégâts à appliquer: 150
[th_power:SpellDamage] Dégâts appliqués - HP: 5200 -> 5050 (-150 dégâts)
[th_power:SpellDamage] HP restant: 5050 / 5200 (97%)
```

### Codes couleur des logs

- **^1Rouge^0** : Dégâts, combat, alertes
- **^2Vert^0** : Succès, HP, protection active
- **^3Jaune^0** : Informations générales
- **^4Cyan^0** : Boucliers, protections
- **^5Magenta^0** : Noms de joueurs
- **^6Blanc^0** : Distances, valeurs numériques

### Logs de debug avancés

Pour activer des logs encore plus détaillés, modifier `th_power/config/config.lua` :

```lua
Config.Debug = true
```

Cela activera des logs supplémentaires pour le débogage avancé.
