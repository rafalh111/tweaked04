---@diagnostic disable: undefined-global, undefined-field
local turtleLib = require("turtleLib")
local utils = require("utils")
local nav = require("nav03")

if utils.ReadAndUnserialize("turtleLog") then
    print("Turtle log found, loading state...")
    TurtleObject = turtleLib.LoadTurtleState()
else
    print("No turtle log found, initializing new turtle state...")
    return
end

local ws = http.websocket("ws://your.server.ip:8080")

local args = { ... }
local WorldMap = turtleLib.downloadMap(ws)


print ("I'm facing: " .. TurtleObject.face)
print ("My position is: " .. TurtleObject.position:tostring())

turtleLib.Journey(TurtleObject, WorldMap, args[1], args[2], args[3])