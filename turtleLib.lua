---@diagnostic disable: undefined-global, undefined-field
local nav = require("nav03")
local utils = require("utils")

local turtleLib = {}

function turtleLib.downladMap(ws)
    ws.send("MapRequest")
    return ws.receive()
end

function turtleLib.LoadTurtleState(ws)
    local TurtleObject = {}
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

        ws.send(textutils.serializeJSON({type = "turtleBorn", payload = TurtleObject}))
        local event, p1, p2, p3 = os.pullEvent()
        message = textutils.unserializeJSON(p2)
        if message.type == "Completion2" then
            TurtleObject = message.payload
        end
        
        utils.SerializeAndSave(TurtleObject, "turtleLog")
    end

    return TurtleObject
end

function turtleLib.Sonar(TurtleObject, WorldMap, InFront, Above, Below, ws)
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
        if inspectVariables.blocked and not WorldMap[vectorKey] then
            WorldMap[vectorKey] = inspectVariables.data;   
        elseif not inspectVariables.blocked and WorldMap[vectorKey] then
            WorldMap[vectorKey] = nil
        end
    end

    ws.send(textutils.serializeJSON({
        type = "MapUpdate",
        payload = detectedChanges
    }))
end

function turtleLib.SafeTurn(TurtleObject, WorldMap, direction, ws)
    if direction == "left" then
        turtle.turnLeft()
        TurtleObject.faceIndex = (TurtleObject.faceIndex - 2) % 4 + 1
        TurtleObject.face = utils.neswDirections[TurtleObject.faceIndex]
    elseif direction == "right" then
        turtle.turnRight()
        TurtleObject.faceIndex = TurtleObject.faceIndex % 4 + 1
        TurtleObject.face = utils.neswDirections[TurtleObject.faceIndex]
    end

    turtleLib.Sonar(TurtleObject, WorldMap, true, false, false)

    utils.SerializeAndSave(TurtleObject, "turtleLog")
end

function turtleLib.SafeMove(TurtleObject, WorldMap, direction, ws)
    local success = false
    if direction == "forward" and turtle.forward() then
        success = true
        turtleLib.Sonar(TurtleObject, WorldMap, true, true, true)
        TurtleObject.position = TurtleObject.position:add(utils.neswudDirectionVectors[TurtleObject.face])
    elseif direction == "up" and turtle.up() then
        success = true
        turtleLib.Sonar(TurtleObject, WorldMap, true, true, false)
        TurtleObject.position = TurtleObject.position:add(utils.neswudDirectionVectors["up"])
    elseif direction == "down" and turtle.down() then
        success = true
        turtleLib.Sonar(TurtleObject, WorldMap, true, false, true)
        TurtleObject.position = TurtleObject.position:add(utils.neswudDirectionVectors["down"])
    end
    
    if success then
        utils.SerializeAndSave(TurtleObject, "turtleLog")
    else
        turtleLib.Sonar(TurtleObject, WorldMap, true, true, true)
    end

    return success
end

function turtleLib.MoveToDirection(TurtleObject, WorldMap, targetFace)
    local success
    
    if targetFace == "up" then
        success = turtleLib.SafeMove(TurtleObject, WorldMap, "up")
    elseif targetFace == "down" then
        success = turtleLib.SafeMove(TurtleObject, WorldMap, "down")
    else
        local diff = (utils.FaceToIndex(targetFace) - TurtleObject.faceIndex) % 4
        
        if diff ~= 0 then
            if diff == 1 then
                turtleLib.SafeTurn(TurtleObject, WorldMap, "right")
            elseif diff == 2 then
                if math.random(1, 2) == 1 then
                    turtleLib.SafeTurn(TurtleObject, WorldMap, "left")
                    turtleLib.SafeTurn(TurtleObject, WorldMap, "left")
                else
                    turtleLib.SafeTurn(TurtleObject, WorldMap, "right")
                    turtleLib.SafeTurn(TurtleObject, WorldMap, "right")
                end
            else
                turtleLib.SafeTurn(TurtleObject, WorldMap, "left")
            end
        end
        
        success = turtleLib.SafeMove(TurtleObject, WorldMap, "forward")
    end

    return success
end

function turtleLib.MoveToNeighbor(TurtleObject, WorldMap, x, y, z)
    local targetV = vector.new(x, y, z)
    local delta = targetV:sub(TurtleObject.position)
    
    if delta:length() ~= 1 then
        return false
    end
    
    local targetFace = utils.duwsenDirectionVectors[delta:tostring()]

    if not turtleLib.MoveToDirection(TurtleObject, WorldMap, targetFace) then
        return false
    end

    return true
end

local function walkPath(TurtleObject, WorldMap, x, y, z, ws)
    local destination = vector.new(x, y, z)
    TurtleObject.busy = true
    
    while not TurtleObject.position:equals(destination) do
        local bestPath = nav.aStar(
            TurtleObject.face,
            TurtleObject.position.x, TurtleObject.position.y, TurtleObject.position.z,
            destination.x, destination.y, destination.z,
            WorldMap
        )
            
        if not bestPath then
            print("I am trapped :(")
            TurtleObject.busy = false
            return false
        end

        print("Best path found with " .. #bestPath .. " steps.")

        ws.send(textutils.serializeJSON({
            type = "Journey",
            payload = {journeyPath = bestPath, turtleID = TurtleObject.id}
        }))

        for _, step in ipairs(bestPath) do
            if InterruptFromMessage then
                print("Path interrupted by websocket message, recalculating...")
                InterruptFromMessage = false
                break
            end

            if not turtleLib.MoveToDirection(TurtleObject, WorldMap, step["direction"]) then
                print("Failed to move to direction: " .. step["direction"])


                for _, passingTurtleID in ipairs(step["turtles"]) do
                    ws.send(textutils.serializeJSON({
                        type = "PassThrough",
                        receiver = passingTurtleID,
                        newHeader = "obstacle on your way",
                        payload = {}
                    }))
                end

                break
            end
        end

        ws.send(textutils.serializeJSON({
            type = "Journeys End",
            payload = {journeyPath = bestPath, turtleID = TurtleObject.id}
        }))
    end

    TurtleObject.busy = false
    return true
end

local function websocketListen()
    while true do
        local event, p1, p2, p3 = os.pullEvent()

        if event ~= "websocket_message" then
            return
        end
        
        local message = textutils.unserializeJSON(p2)

        if not message.type == "obstacle on your way" then
            return
        end

        InterruptFromMessage = true
    end
end

function turtleLib.Journey(TurtleObject, WorldMap, x, y, z, ws)
    InterruptFromMessage = false
    parallel.waitForAny(
        function()
            walkPath(TurtleObject, WorldMap, x, y, z, ws)
        end,

        function()
            websocketListen()
        end
    )
end

return turtleLib