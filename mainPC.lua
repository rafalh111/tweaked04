local turtleApi = require("turtleApi")
local utils = require("utils")
local nav = require("nav03")
local rednet
local textutils
local os

local Obstacles = utils.ReadAndUnserialize("map") or {}
local updateQueue = {}
while true do
    local senderID, message, protocol = rednet.receive()
    if protocol == "MapRequest" then
        rednet.send(senderID, textutils.serialise(Obstacles), "MapSupply")
    elseif protocol == "MapUpdate" then
        local detectedChanges = textutils.unserialise(message)
        for vectorKey, inspectVariables in pairs(detectedChanges) do
            if inspectVariables == "phantom" then
                Obstacles[vectorKey] = nil
            else
                Obstacles[vectorKey] = inspectVariables
            end
        end

        utils.SerializeAndSave(Obstacles, "map")
    end

    os.queueEvent("yield")
    os.pullEvent()
end