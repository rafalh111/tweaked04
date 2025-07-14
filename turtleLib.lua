local nav = require("nav03")
local utils = require("utils")
local vector = require("vector")
local turtle = require("turtle")
local rednet
local textutils

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
    local TurtleObject
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

    return TurtleObject
end

function turtleLib.SendLogToBase(TurtleObject, id)
    if id and TurtleObject then
        rednet.send(id, textutils.serialise(TurtleObject))
    end
end

function turtleLib.Sonar(TurtleObject, Obstacles, InFront, Above, Below, ws)
    local detectedChanges = {}

    if InFront then
        local blockInFrontVectorKey = TurtleObject.position:add(neswudDirectionVectors[TurtleObject.face]):tostring()
        local blockedForward, dataForward = turtle.inspect()
        detectedChanges[blockInFrontVectorKey] = {blocked = blockedForward, data = dataForward.name}
    end

    if Above then
        local blockAboveVectorKey = TurtleObject.position:add(neswudDirectionVectors["up"]):tostring()
        local blockedUp, dataUp = turtle.inspectUp()
        detectedChanges[blockAboveVectorKey] = {blocked = blockedUp, data = dataUp.name}
    end

    if Below then
        local blockBelowVectorKey = TurtleObject.position:add(neswudDirectionVectors["down"]):tostring()
        local blockedDown, dataDown = turtle.inspectDown()
        detectedChanges[blockBelowVectorKey] = {blocked = blockedDown, data = dataDown.name}
    end

    local message = {type = "MapUpdate", payload = detectedChanges}
    ws.send(textutils.serializeJSON(message))

    -- local changeDetected = false
    -- for vectorKey, inspectVariables in pairs(detectedChanges) do
    --     if inspectVariables.blocked and not Obstacles[vectorKey] then
    --         changeDetected = true
    --     elseif not inspectVariables.blocked and Obstacles[vectorKey] then
    --         detectedChanges[vectorKey] = "phantom"
    --         changeDetected = true
    --     else
    --         detectedChanges[vectorKey] = nil
    --     end
    -- end

    -- if changeDetected then
    --     rednet.send(TurtleObject.baseID, textutils.serialize(detectedChanges), "MapUpdate")
    -- end
end

function turtleLib.SafeTurn(TurtleObject, Obstacles, direction)
    if direction == "left" then
        turtle.turnLeft()
        TurtleObject.faceIndex = (TurtleObject.faceIndex - 2) % 4 + 1
        TurtleObject.face = neswDirections[TurtleObject.faceIndex]
    elseif direction == "right" then
        turtle.turnRight()
        TurtleObject.faceIndex = TurtleObject.faceIndex % 4 + 1
        TurtleObject.face = neswDirections[TurtleObject.faceIndex]
    end

    turtleLib.Sonar(TurtleObject, Obstacles, true, false, false)
    utils.SerializeAndSave(TurtleObject, "turtleLog")
end

function turtleLib.SafeMove(TurtleObject, Obstacles, direction)
    local success = false
    if direction == "forward" and turtle.forward() then
        success = true
        turtleLib.Sonar(TurtleObject, Obstacles, true, true, true)
        TurtleObject.position = TurtleObject.position:add(neswudDirectionVectors[TurtleObject.face])
    elseif direction == "up" and turtle.up() then
        success = true
        turtleLib.Sonar(TurtleObject, Obstacles, true, true, false)
        TurtleObject.position = TurtleObject.position:add(neswudDirectionVectors["up"])
    elseif direction == "down" and turtle.down() then
        success = true
        turtleLib.Sonar(TurtleObject, Obstacles, true, false, true)
        TurtleObject.position = TurtleObject.position:add(neswudDirectionVectors["down"])
    end
    
    if success then
        utils.SerializeAndSave(TurtleObject, "turtleLog")
    else
        turtleLib.Sonar(TurtleObject, Obstacles, true, true, true)
    end

    return success
end

function turtleLib.MoveToDirection(TurtleObject, Obstacles, targetFace)
    local success
    
    if targetFace == "up" then
        success = turtleLib.SafeMove(TurtleObject, Obstacles, "up")
    elseif targetFace == "down" then
        success = turtleLib.SafeMove(TurtleObject, Obstacles, "down")
    else
        local diff = (turtleLib.FaceToIndex(targetFace) - TurtleObject.faceIndex) % 4
        
        if diff ~= 0 then
            if diff == 1 then
                turtleLib.SafeTurn(TurtleObject, Obstacles, "right")
            elseif diff == 2 then
                if math.random(1, 2) == 1 then
                    turtleLib.SafeTurn(TurtleObject, Obstacles, "left")
                    turtleLib.SafeTurn(TurtleObject, Obstacles, "left")
                else
                    turtleLib.SafeTurn(TurtleObject, Obstacles, "right")
                    turtleLib.SafeTurn(TurtleObject, Obstacles, "right")
                end
            else
                turtleLib.SafeTurn(TurtleObject, Obstacles, "left")
            end
        end
        
        success = turtleLib.SafeMove(TurtleObject, Obstacles, "forward")
    end

    return success
end

function turtleLib.MoveToNeighbor(TurtleObject, Obstacles, x, y, z)
    local targetV = vector.new(x, y, z)
    local delta = targetV:sub(TurtleObject.position)
    
    if delta:length() ~= 1 then
        return
    end
    
    local targetFace = duwsenDirectionVectors[delta:tostring()]

    if not turtleLib.MoveToDirection(TurtleObject, Obstacles, targetFace) then
        return false
    end

    return true
end

function turtleLib.Journey(TurtleObject, Obstacles, x, y, z)
    local destination = vector.new(x, y, z)
    TurtleObject.busy = true
    
    while not TurtleObject.position:equals(destination) do
        if not Obstacles then
            rednet.send(TurtleObject.id, "Journey", "MapRequest")
            local senderID, message, protocol = rednet.receive()
            if protocol == "MapSupply" then
                Obstacles = textutils.unserialize(message)
            end
        end

        local bestPath = nav.aStar(
            TurtleObject.position.x, TurtleObject.position.y, TurtleObject.position.z,
            destination.x, destination.y, destination.z, Obstacles
        )

        if not bestPath then
            --print("I am trapped :(")
            TurtleObject.busy = false
            return false
        end

        for _, step in ipairs(bestPath) do
            if not turtleLib.MoveToDirection(TurtleObject, Obstacles, step["direction"]) then
                break
            end
        end
    end

    TurtleObject.busy = false
    return true
end

return turtleLib