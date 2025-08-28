---@diagnostic disable: undefined-global, undefined-field
local turtleLib = require("turtleLib")
local utils = require("utils")
local nav = require("nav03")

local ws, err = http.websocket("ws://127.0.0.1:8080")
if not ws then
    error("WebSocket failed: " .. tostring(err))
end

-- load or initialize turtle state
local TurtleObject = turtleLib.LoadTurtleState(ws)
TurtleObject.busy = false

-- command lookup
local commandHandlers = {
    journey = function(args)
        turtleLib.Journey(
            TurtleObject,
            args.destinations, 
            args.doAtTheEnd, 
            ws
        )
    end,
}

while true do
    local event, url, data = os.pullEvent()

    if event == "websocket_message" then
        local message = textutils.unserializeJSON(data)
        if not message then
            print("Invalid JSON: " .. tostring(data))
        else
            if message.type == "Completion2" then
                TurtleObject = message.payload
                utils.SerializeAndSave(TurtleObject, "turtleLog")

            elseif message.type == "PC?" then
                -- announce we are a turtle
                ws.send(textutils.serializeJSON({
                    type = "TurtleBorn",
                    payload = TurtleObject
                }))

            elseif message.type == "Task" then
                local cmd = message.payload.command
                local args = message.payload.args or {}

                if commandHandlers[cmd] then
                    TurtleObject.busy = true
                    commandHandlers[cmd](args)
                    TurtleObject.busy = false
                else
                    print("Unknown command: " .. tostring(cmd))
                end
            end
        end
    end
end