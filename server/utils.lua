local function safeMerge(dst, src)
    if not dst then dst = {} end
    if not src then return dst end
    for k, v in pairs(src) do
        if dst[k] == nil then dst[k] = v end
    end
    return dst
end

local Utils = {}

function Utils.LogSpellCast(data)
    data = data or {}

    if not _G.TH_Power or not _G.TH_Power.Log then
        if Config and Config.Logs and Config.Logs.debug then
            print('[dvr_power] Utils.LogSpellCast: Log module absent, impossible d\'envoyer le log')
        end
        return
    end

    safeMerge(data, {
        professor = {},
        target = {},
        spell = {},
        context = {}
    })

    _G.TH_Power.Log('spell_cast', data)
end

_G.THPowerUtils = _G.THPowerUtils or {}
_G.THPowerUtils.LogSpellCast = Utils.LogSpellCast

function LogSpellCast(data)
    return Utils.LogSpellCast(data)
end

return Utils
