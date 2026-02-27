---@diagnostic disable: trailing-space, undefined-global
local loadedModules = {}

local function LoadModule(moduleName) 
    if loadedModules[moduleName] then
        return
    end
    
    if not Config.IsModuleAllowed(moduleName) then
        return
    end
    
    local modulePath <const> = Config.Modules.modulesPath .. moduleName .. '/client/main.lua'
    local moduleCode <const> = LoadResourceFile(GetCurrentResourceName(), modulePath)
    
    if not moduleCode then
        return
    end

    local chunk, err = load(moduleCode, modulePath, 't', _ENV)
    if not chunk then
        return
    end

    local ok, loadErr = pcall(chunk)
    if not ok then
        return
    end

    loadedModules[moduleName] = true
end

_ENV.dvr_power_loadModule = LoadModule
