---@diagnostic disable: undefined-field
local turtleApi = require("turtleProgram03")
local utils = require("utils")
local nav = require("nav03")
local args = { ... }

local data = turtleApi.LoadTurtleState()
rednet.send(data["baseID"], "new turtle with ID:" .. data.id)

while true do
    local id, message = rednet.receive()
    if data and id == data["baseID"] then
        load(message)()
    end

    os.queueEvent("yield")
    os.pullEvent()
end