---@diagnostic disable: undefined-field
local turtleApi = require("turtleApi")
local utils = require("utils")
local nav = require("nav03")
local rednet


local ws, err = http.websocket("ws://your.server.ip:port")

local TurtleObject = turtleApi.LoadTurtleState()
rednet.send(TurtleObject["baseID"], "new turtle with ID:" .. TurtleObject.id)

while true do
    local id, message = rednet.receive()
    if id == TurtleObject["baseID"] then
        load(message)()
    end

    os.queueEvent("yield")
    os.pullEvent()
end