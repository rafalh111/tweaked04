---@diagnostic disable: undefined-global, undefined-field
local nav = require("nav03")
local utils = require("utils")

local turtleLib = {}

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

function turtleLib.SafeMove(TurtleObject, WorldMap, direction, i, ws)
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
        if i then
            TurtleObject["journeyStepIndex"] = i
        end

        utils.SerializeAndSave(TurtleObject, "turtleLog")
    else
        turtleLib.Sonar(TurtleObject, WorldMap, true, true, true)
    end

    return success
end

function turtleLib.MoveToDirection(TurtleObject, WorldMap, targetFace, i)
    local success
    
    if targetFace == "up" then
        success = turtleLib.SafeMove(TurtleObject, WorldMap, "up", i)
    elseif targetFace == "down" then
        success = turtleLib.SafeMove(TurtleObject, WorldMap, "down", i)
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
        
        success = turtleLib.SafeMove(TurtleObject, WorldMap, "forward", i)
    end

    return success
end

function turtleLib.MoveToNeighbor(TurtleObject, WorldMap, x, y, z, i)
    local targetV = vector.new(x, y, z)
    local delta = targetV:sub(TurtleObject.position)
    
    if delta:length() ~= 1 then
        return false
    end
    
    local targetFace = utils.duwsenDirectionVectors[delta:tostring()]

    if not turtleLib.MoveToDirection(TurtleObject, WorldMap, targetFace, i) then
        return false
    end

    return true
end

local function intersectionHandle(step, turtleObject, i, ws)
    local companionIDs = turtleObject["journeyPath"][i - 1]["turtles"]

    repeat
        ws.send(textutils.serializeJSON({
            type = "TurtleScan",
            payload = step["turtles"]
        }))
        
        local intercectioners = utils.listenForWsMessage("TurtleScanResult")

        if #intercectioners == 0 then 
            return
        end
        
        local problematicTurtles = {}
        for _, suspect in ipairs(intercectioners) do
            local collider = true
            for _, companionID in ipairs(companionIDs) do
                if suspect["id"] == companionID then
                    collider = false
                end
            end

            if collider == true then
                table.insert(problematicTurtles, suspect)
            end
        end
        
        if #problematicTurtles == 0 then
            return
        end
        
        local mergePossible = true
        local highestDiff = 0
        for _, problematicTurtle in ipairs(problematicTurtles) do
            for intersectionIndex, problematicStep in ipairs(problematicTurtle["journeyPath"]) do
                if problematicStep["vector"] == step["vector"] then
                    local diff = intersectionIndex - problematicTurtle["journeyStepIndex"]
                    if diff <= 3 and diff > highestDiff then                   
                        highestDiff = diff
                        mergePossible = false
                    end
                end
            end
        end
        
        if not mergePossible then
            os.sleep(highestDiff)
        end
    until not mergePossible
end

local function handleMovement(TurtleObject, WorldMap, step, i, ws)
    if not turtleLib.MoveToDirection(TurtleObject, WorldMap, step, i) then
        print("Failed to move to direction: " .. step["direction"])
        
        for _, passingTurtleID in ipairs(step["turtles"]) do
            ws.send(textutils.serializeJSON({
                type = "PassThrough",
                receiver = passingTurtleID,
                newHeader = "obstacle on your way",
                payload = { roadBlock = TurtleObject.position:add(utils.neswudDirectionVectors[step["direction"]]) }
            }))
        end

        return false
    end
end

local function subJourney(TurtleObject, WorldMap, destination, doAtTheEnd, i, ws)
    TurtleObject.busy = true
    repeat
        local journeyPath = nav.aStar(TurtleObject.face, TurtleObject.position, destination, WorldMap)
        
        if not journeyPath then
            print("I am trapped :(")
            TurtleObject["journeyStepIndex"] = nil
            TurtleObject["journeyPath"] = nil
            TurtleObject.busy = false
            return false
        end
        
        TurtleObject["journeyStepIndex"] = i

        if not doAtTheEnd or doAtTheEnd ~= "go" then
            destination = journeyPath[#journeyPath - 1]["vector"]
        end
        
        TurtleObject['journeyPath'] = journeyPath

        print("Best path found with " .. #journeyPath .. " steps.")

        ws.send(textutils.serializeJSON({
            type = "Journey",
            payload = {journeyPath = journeyPath, turtleID = TurtleObject.id}
        }))

        for i, step in ipairs(journeyPath) do
            if InterruptFromMessage then
                print("Path interrupted by websocket message, recalculating...")
                InterruptFromMessage = false
                break
            end

            if not step["special"]["lastBlock"] or step["special"]["lastBlock"] == "go" then
                if step["special"]["intersection"] then
                    intersectionHandle(step, journeyPath, i, ws)
                    local ins = utils.getNeighbors(step["vector"])
                    ws.send(textutils.serializeJSON({
                        type = "intersection",
                        payload = utils.getNeighbors(step["vector"])
                    }))

                    local message = utils.listenForWsMessage("intersectionData")

                end

                handleMovement(TurtleObject, WorldMap, step["direction"], i, ws)
            end


        end

        TurtleObject["journeyStepIndex"] = nil
        TurtleObject["journeyPath"] = nil

        ws.send(textutils.serializeJSON({
            type = "Journeys End",
            payload = {journeyPath = journeyPath, turtleID = TurtleObject.id}
        }))
    until TurtleObject.position == destination

    TurtleObject["busy"] = false
    return true
end

local function checkForInterruptions(TurtleObject)
    while true do
        local message = utils.listenForWsMessages({"obstacle on your way", "new turtle on your path"})

        for i = TurtleObject["journeyStepIndex"] + 1, #TurtleObject["journeyPath"] do
            if TurtleObject["journeyPath"][i]:tostring() == message["payload"]["roadBlock"]:tostring() then
                InterruptFromMessage = true
                break
            end
        end
    end
end

function turtleLib.Journey(TurtleObject, WorldMap, destination, doAtTheEnd, ws)
    InterruptFromMessage = false
    parallel.waitForAny(
        function()
            subJourney(TurtleObject, WorldMap, destination, doAtTheEnd, ws)
        end,

        function()
            checkForInterruptions(TurtleObject)
        end
    )
end

return turtleLib