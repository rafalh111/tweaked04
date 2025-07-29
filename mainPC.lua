local turtleLib = require("turtleLib")
local utils = require("utils")
local nav = require("nav03")
local rednet
local textutils
local os
local vector = require("vector")
local http = require("http")

local ws, err = http.websocket("ws://127.0.0.1:8080")
-- local updateQueue = {}

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "websocket_message" then
        local message = textutils.unserializeJSON(p1)

        if message.type == "PC?" then
            ws.send("PCConfirm")
        end
    end

    if event == "rednet_message" then
        local senderID, message, protocol = p1, p2, p3

        if protocol == "TurtleBorn" then
            local TurtleObject = {
                position = vector.new(22, 79, 45),
                face = "south",
                faceIndex = 3,
                id = turtle.getID(),
                busy = false,
            }

            rednet.send(senderID, textutils.serialize(TurtleObject), "Completion1")
        end
    end
end