local nav = require("nav022")
local utils = require("utils")--local vector = require("vector")
local turtle

local turtleLib = {}

local neswDirections = {"north", "east","south", "west"}
local neswudDirectionVectors = {
    ["north"] = vector.new(0, 0, -1), -- north
    ["east"] = vector.new(1, 0, 0),   -- east
    ["south"] = vector.new(0, 0, 1),  -- south
    ["west"] = vector.new(-1, 0, 0),  -- west
    ["up"] = vector.new(0, 1, 0),     -- up
    ["down"] = vector.new(0, -1, 0)   -- down
}

local duwsenDirectionVectors = {
    [vector.new(0, 0, -1):tostring()] = "north",
    [vector.new(1, 0, 0):tostring()] = "east",
    [vector.new(0, 0, 1):tostring()] = "south",
    [vector.new(-1, 0, 0):tostring()] = "west",
    [vector.new(0, 1, 0):tostring()] = "up",
    [vector.new(0, -1, 0):tostring()] = "down"
}

function turtleLib.FaceToIndex(face)
    for index, direction in ipairs(neswDirections) do
        if direction == face then
            return index
        end
    end
end

function turtleLib.LoadTurtleState()
    local turtleLog = utils.ReadAndUnserialize("turtleLog")

    if turtleLog then
        TurtleObject = turtleLog
        TurtleObject.position = vector.new(TurtleObject.position.x, TurtleObject.position.y, TurtleObject.position.z)
    else
        TurtleObject = {
            position = vector.new(22, 79, 45),
            face = "south",
            faceIndex = 3,
            id = turtle.getID(),
            busy = false,
        }
    end
end

function turtleLib.Sonar(InFront, Above, Below)
    local inspectTable = {}

    if InFront then
        local blockInFrontVectorKey = TurtleObject.position:add(neswudDirectionVectors[TurtleObject.face]):tostring()
        local blockedForward, dataForward = turtle.inspect()
        inspectTable[blockInFrontVectorKey] = {blocked = blockedForward, data = dataForward.name}
    end

    if Above then
        local blockAboveVectorKey = TurtleObject.position:add(neswudDirectionVectors["up"]):tostring()
        local blockedUp, dataUp = turtle.inspectUp()
        inspectTable[blockAboveVectorKey] = {blocked = blockedUp, data = dataUp.name}
    end

    if Below then
        local blockBelowVectorKey = TurtleObject.position:add(neswudDirectionVectors["down"]):tostring()
        local blockedDown, dataDown = turtle.inspectDown()
        inspectTable[blockBelowVectorKey] = {blocked = blockedDown, data = dataDown.name}
    end

    local Obstacles = utils.ReadAndUnserialize("map") or {}

    local changeDetected = false
    for vectorKey, inspectVariables in pairs(inspectTable) do
        if inspectVariables.blocked and not Obstacles[vectorKey] then
            -- if not inspectVariables.data == "computercraft:turtle_advanced" then
            --     Obstacles[vectorKey] = inspectVariables.data
            --     changeDetected = true
            -- else
            --     os.sleep(5)  -- Avoid rapid updates
            -- end
            Obstacles[vectorKey] = inspectVariables.data
            changeDetected = true
        elseif not inspectVariables.blocked and Obstacles[vectorKey] then
            Obstacles[vectorKey] = nil
            changeDetected = true
        end
    end

    if changeDetected then
        utils.SerializeAndSave(Obstacles, "map")
    end

    return inspectTable
end

function turtleLib.SafeTurn(TurtleObject, direction)
    if direction == "left" then
        turtle.turnLeft()
        TurtleObject.faceIndex = (TurtleObject.faceIndex - 2) % 4 + 1
        TurtleObject.face = neswDirections[TurtleObject.faceIndex]
    elseif direction == "right" then
        turtle.turnRight()
        TurtleObject.faceIndex = TurtleObject.faceIndex % 4 + 1
        TurtleObject.face = neswDirections[TurtleObject.faceIndex]
    end

    turtleLib.Sonar(true, false, false)
    utils.SerializeAndSave(TurtleObject, "turtleLog")
end

function turtleLib.SafeMove(TurtleObject, direction)
    local success = false
    if direction == "forward" and turtle.forward() then
        success = true
        turtleLib.Sonar(true, true, true)
        TurtleObject.position = TurtleObject.position:add(neswudDirectionVectors[TurtleObject.face])
    elseif direction == "up" and turtle.up() then
        success = true
        turtleLib.Sonar(true, true, false)
        TurtleObject.position = TurtleObject.position:add(neswudDirectionVectors["up"])
    elseif direction == "down" and turtle.down() then
        success = true
        turtleLib.Sonar(true, false, true)
        TurtleObject.position = TurtleObject.position:add(neswudDirectionVectors["down"])
    end
    
    if success then
        utils.SerializeAndSave(TurtleObject, "turtleLog")
    else
        turtleLib.Sonar(true, true, true)
    end

    return success
end

function turtleLib.MoveToDirection(TurtleObject, targetFace)
    local success

    if targetFace == "up" then
        success = turtleLib.SafeMove(TurtleObject, "up")
    elseif targetFace == "down" then
        success = turtleLib.SafeMove(TurtleObject, "down")
    else
        local diff = (turtleLib.FaceToIndex(targetFace) - TurtleObject.faceIndex) % 4

        if diff == 1 then
            turtleLib.SafeTurn(TurtleObject, "right")
        elseif diff == 2 then
            if math.random(1, 2) == 1 then
                turtleLib.SafeTurn(TurtleObject, "left")
                turtleLib.SafeTurn(TurtleObject, "left")
            else
                turtleLib.SafeTurn(TurtleObject, "right")
                turtleLib.SafeTurn(TurtleObject, "right")
            end
        elseif diff == 3 then
            turtleLib.SafeTurn(TurtleObject, "left")
        end
        
        success = turtleLib.SafeMove(TurtleObject, "forward")
    end

    return success
end

function turtleLib.Step(TurtleObject, x, y, z)
    local targetV = vector.new(x, y, z)
    local delta = targetV:sub(TurtleObject.position)
    
    if delta:length() ~= 1 then
        return
    end
    
    local targetFace = duwsenDirectionVectors[delta:tostring()]

    if not turtleLib.MoveToDirection(TurtleObject, targetFace) then
        return false
    end

    return true
end

function turtleLib.Journey(TurtleObject, x, y, z)
    local destination = vector.new(x, y, z)
    TurtleObject.busy = true

    while not TurtleObject.position:equals(destination) do
        local bestPath = nav.aStar(
            TurtleObject.position.x, TurtleObject.position.y, TurtleObject.position.z,
            destination.x, destination.y, destination.z
        )

        if not bestPath then
            --print("I am trapped :(")
            TurtleObject.busy = false
            return false
        end
        
        for _, step in ipairs(bestPath) do
            if not turtleLib.Step(TurtleObject, step["vector"].x, step["vector"].y, step["vector"].z) then
                break
            end
        end
    end

    TurtleObject.busy = false
    return true
end

return turtleLib