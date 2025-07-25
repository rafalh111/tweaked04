---@diagnostic disable: undefined-global, undefined-field
local nav = require("nav03")
local utils = require("utils")

local turtleLib = {}

function turtleLib.downladMap(ws)
    ws.send("MapRequest")
    return ws.receive()
end

function turtleLib.LoadTurtleState(ws)
    local TurtleObject
    local turtleLog = utils.ReadAndUnserialize("turtleLog")

    if turtleLog then
        TurtleObject = turtleLog
        TurtleObject.position = vector.new(TurtleObject.position.x, TurtleObject.position.y, TurtleObject.position.z)
    else
        rednet.send(TurtleObject["baseID"], TurtleObject, "TurtleBorn")
        local senderID, message, protocol = rednet.receive()
        if protocol == "Completion1" then
            message = textutils.unserialize(message)
            TurtleObject = message
        end

        -- local messageToSend = {type = "turtleBorn", payload = TurtleObject}
        -- ws.send(textutils.serializeJSON(messageToSend))
        -- local message = ws.receive()
        -- message = textutils.unserializeJSON(ws.receive())
        -- if message.type == "Completion2" then
        --     TurtleObject = message.payload
        -- end

        utils.SerializeAndSave(TurtleObject, "turtleLog")
    end

    return TurtleObject
end

function turtleLib.Sonar(TurtleObject, Obstacles, InFront, Above, Below, ws)
    local detectedChanges = {}

    if InFront then
        local blockInFrontVectorKey = TurtleObject.position:add(utils.neswudDirectionVectors[TurtleObject.face]):tostring()
        local blockedForward, dataForward = turtle.inspect()
        detectedChanges[blockInFrontVectorKey] = {blocked = blockedForward, data = dataForward.name}
    end

    if Above then
        local blockAboveVectorKey = TurtleObject.position:add(utils.neswudDirectionVectors["up"]):tostring()
        local blockedUp, dataUp = turtle.inspectUp()
        detectedChanges[blockAboveVectorKey] = {blocked = blockedUp, data = dataUp.name}
    end

    if Below then
        local blockBelowVectorKey = TurtleObject.position:add(utils.neswudDirectionVectors["down"]):tostring()
        local blockedDown, dataDown = turtle.inspectDown()
        detectedChanges[blockBelowVectorKey] = {blocked = blockedDown, data = dataDown.name}
    end

    for vectorKey, inspectVariables in pairs(detectedChanges) do
        if inspectVariables.blocked and not Obstacles[vectorKey] then
            Obstacles[vectorKey] = inspectVariables.data;   
        elseif not inspectVariables.blocked and Obstacles[vectorKey] then
            Obstacles[vectorKey] = nil
        end
    end

    -- local message = {type = "MapUpdate", payload = detectedChanges}
    -- ws.send(textutils.serializeJSON(message))
end

function turtleLib.SafeTurn(TurtleObject, Obstacles, direction, ws)
    if direction == "left" then
        turtle.turnLeft()
        TurtleObject.faceIndex = (TurtleObject.faceIndex - 2) % 4 + 1
        TurtleObject.face = utils.neswDirections[TurtleObject.faceIndex]
    elseif direction == "right" then
        turtle.turnRight()
        TurtleObject.faceIndex = TurtleObject.faceIndex % 4 + 1
        TurtleObject.face = utils.neswDirections[TurtleObject.faceIndex]
    end

    turtleLib.Sonar(TurtleObject, Obstacles, true, false, false)

    utils.SerializeAndSave(TurtleObject, "turtleLog")
end

function turtleLib.SafeMove(TurtleObject, Obstacles, direction, ws)
    local success = false
    if direction == "forward" and turtle.forward() then
        success = true
        turtleLib.Sonar(TurtleObject, Obstacles, true, true, true)
        TurtleObject.position = TurtleObject.position:add(utils.neswudDirectionVectors[TurtleObject.face])
    elseif direction == "up" and turtle.up() then
        success = true
        turtleLib.Sonar(TurtleObject, Obstacles, true, true, false)
        TurtleObject.position = TurtleObject.position:add(utils.neswudDirectionVectors["up"])
    elseif direction == "down" and turtle.down() then
        success = true
        turtleLib.Sonar(TurtleObject, Obstacles, true, false, true)
        TurtleObject.position = TurtleObject.position:add(utils.neswudDirectionVectors["down"])
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
        local diff = (utils.FaceToIndex(targetFace) - TurtleObject.faceIndex) % 4
        
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
    
    local targetFace = utils.duwsenDirectionVectors[delta:tostring()]

    if not turtleLib.MoveToDirection(TurtleObject, Obstacles, targetFace) then
        return false
    end

    return true
end

function turtleLib.Journey(TurtleObject, Obstacles, x, y, z, ws)
    local destination = vector.new(x, y, z)
    TurtleObject.busy = true
    
    while not TurtleObject.position:equals(destination) do
        local bestPath = nav.aStar(
            TurtleObject.face,
            TurtleObject.position.x, TurtleObject.position.y, TurtleObject.position.z,
            destination.x, destination.y, destination.z,
            Obstacles
        )
            
        if not bestPath then
            --print("I am trapped :(")
            TurtleObject.busy = false
            return false
        end

        print("Best path found with " .. #bestPath .. " steps.")
        local messageToSend = {
            type = "Journey",
            payload = bestPath,
        }

        ws.send(textutils.serializeJSON(messageToSend))

        for _, step in ipairs(bestPath) do
            if not turtleLib.MoveToDirection(TurtleObject, Obstacles, step["direction"]) then
                print("Failed to move to direction: " .. step["direction"])
                break
            end
        end

        messageToSend["type"] = "Journeys end" 
        ws.send(textutils.serializeJSON(messageToSend))
    end

    TurtleObject.busy = false
    return true
end

return turtleLib