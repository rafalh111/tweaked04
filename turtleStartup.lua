---@diagnostic disable: undefined-global, undefined-field
local turtleLib = require("turtleLib")
local utils = require("utils")
local nav = require("nav03")


local ws, err = http.websocket("ws://your.server.ip:8080")

local TurtleObject = turtleLib.LoadTurtleState(ws)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "websocket_message" then
        local message = textutils.unserializeJSON(p1)

        if message.type == "Completion" then
            TurtleObject = message.payload
            utils.SerializeAndSave(TurtleObject, "turtleLog")
        end

        if message.type == "PC?" then
            ws.send("notPC")
        end
    end

    if event == "rednet_message" then
        local senderID, message, protocol = p1, p2, p3

        if message == "Scan" then
            rednet.send(senderID, textutils.serialize(TurtleObject), "ScanResponse")
        end
    end
end