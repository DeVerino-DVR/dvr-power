---@diagnostic disable: undefined-global, trailing-space
lib.callback.register('dvr_power:getPlayerSpells', function(source)
    local player <const> = ESX.GetPlayerFromId(source)
    if not player then return {} end
    
    local identifier = player.identifier
    local unlockedSpells = {}
    
    local result = MySQL.query.await('SELECT spell_id FROM character_spells WHERE identifier = ?', {identifier})
    
    if result then
        for _, row in ipairs(result) do
            table.insert(unlockedSpells, row.spell_id)
        end
    end

    return unlockedSpells
end)

RegisterNetEvent('dvr_power:castSpell', function(spellId)
    if not spellId then return end
    local sourceId <const> = source
    local cooldown = GetSpellCooldown(spellId)

    TriggerClientEvent('dvr_power:onSpellCast', sourceId, {
        id = spellId,
        cooldown = cooldown
    })
end)
