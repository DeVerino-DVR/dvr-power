local BlockWeaponWheelThisFrame = BlockWeaponWheelThisFrame
local DisableControlAction = DisableControlAction
local DisplayRadar = DisplayRadar
local IsPedArmed = IsPedArmed
local PlayerPedId = PlayerPedId
local Wait = Wait

CreateThread(function()
    while true do
        local playerPed = PlayerPedId()

        BlockWeaponWheelThisFrame()
        DisableControlAction(0, 37, true)
        DisableControlAction(0, 199, true)
        DisableControlAction(1, 159, true)
        DisableControlAction(1, 161, true)
        DisableControlAction(1, 104, true)
        DisableControlAction(1, 163, true)
        DisableControlAction(1, 162, true)

        if IsPedArmed(playerPed, 6) then
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
        end

        DisplayRadar(false)
        Wait(0)
    end
end)