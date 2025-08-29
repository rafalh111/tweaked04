---@diagnostic disable: undefined-global, undefined-field
local turtleLib = require("turtleLib")
local utils = require("utils")
local nav = require("nav03")
print("Loaded the libraries successfully")
os.sleep(0.5)

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

print("Initialized commandHandlers")
os.sleep(0.5)


local ws
while not ws do
    local err
    ws, err = http.websocket("ws://127.0.0.1:8080")
    if err then
        error("No signal::: " .. tostring(err) .. " :::will try again after 5 seconds")
    end
    os.sleep(5)
end

print("connected to the server!!!")
os.sleep(0.5)

-- load or initialize turtle state
local defaultTurtle = {}
local TurtleObject = turtleLib.LoadTurtleState(ws, defaultTurtle)
TurtleObject.busy = false

print("loaded the turtle data correctly, starting the main loop...")

while true do
    local event, url, data = os.pullEvent()

    if event == "websocket_message" then
        local message = textutils.unserializeJSON(data)
        if not message then
            print("Invalid JSON: " .. tostring(data))
            goto continue
        end
        
        if message.type == "Journey" then
            TurtleObject.busy = true

            local args = message.payload.args
            commandHandlers[journey](args)

            TurtleObject.busy = false
        elseif message.type == "PC?" then
            -- announce we are a turtle
            ws.send(textutils.serializeJSON({
                type = "PC? Response",
                payload = {
                    TurtleObject = TurtleObject,
                    letter = "notPC"
                }
            }))
        elseif message.type == "Task" then
            local cmds = message.payload.commands
            TurtleObject.busy = true
            
            for _, cmd in ipairs(cmds) do               
                if commandHandlers[cmd.name] then
                    commandHandlers[cmd.name](cmd.args)
                else
                    print("Unknown command: " .. tostring(cmd))
                    break
                end
            end

            TurtleObject.busy = false
        end
    end

    ::continue::
end