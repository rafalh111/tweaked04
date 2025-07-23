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

local args = { ... }
local Obstacles = {}

print ("I'm facing: " .. TurtleObject.face)
print ("My position is: " .. TurtleObject.position:tostring())

turtleLib.Journey(TurtleObject, Obstacles, args[1], args[2], args[3])