--@diagnostic disable: undefined-global, undefined-field
local nav = require("nav03")
local utils = require("utils")
local textutils
local os
local rednet
local parallel

local turtleLib = {}

function turtleLib.LoadTurtleState(ws)
    local TurtleObject = {}
    local turtleLog = utils.ReadAndUnserialize("turtleLog")

    if turtleLog then
        TurtleObject = turtleLog
        TurtleObject["position"] = vector.new(TurtleObject["position"].x, TurtleObject["position"].y, TurtleObject["position"].z)
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
        local vectorKey = TurtleObject["position"]:add(utils.neswudDirectionVectors[TurtleObject["face"]]):tostring()
        local blocked, data = turtle.inspect()
        detectedChanges[vectorKey] = {blocked = blocked, data = data.name}
    end

    if Above then
        local vectorKey = TurtleObject["position"]:add(utils.neswudDirectionVectors["up"]):tostring()
        local blocked, data = turtle.inspectUp()
        detectedChanges[vectorKey] = {blocked = blocked, data = data.name}
    end

    if Below then
        local vectorKey = TurtleObject["position"]:add(utils.neswudDirectionVectors["down"]):tostring()
        local blocked, data = turtle.inspectDown()
        detectedChanges[vectorKey] = {blocked = blocked, data = data.name}
    end

    for vectorKey, inspectVariables in pairs(detectedChanges) do
        if inspectVariables.blocked and not WorldMap[vectorKey] then
            WorldMap[vectorKey] = inspectVariables.data;
            WorldMap[vectorKey]["blocked"] = true
        elseif not inspectVariables.blocked and WorldMap[vectorKey] then
            WorldMap[vectorKey] = nil
        end
    end

    ws.send(textutils.serializeJSON({
        type = "MapUpdate",
        payload = detectedChanges
    }))
end

function turtleLib.SafeTurn(TurtleObject, WorldMap, direction)
    if direction == "left" then
        turtle.turnLeft()
        TurtleObject["faceIndex"] = (TurtleObject["faceIndex"] - 2) % 4 + 1
        TurtleObject["face"] = utils.neswDirections[TurtleObject["faceIndex"]]
    elseif direction == "right" then
        turtle.turnRight()
        TurtleObject["faceIndex"] = TurtleObject["faceIndex"] % 4 + 1
        TurtleObject["face"] = utils.neswDirections[TurtleObject["faceIndex"]]
    end

    turtleLib.Sonar(TurtleObject, WorldMap, true, false, false)

    utils.SerializeAndSave(TurtleObject, "turtleLog")
end

function turtleLib.SafeMove(TurtleObject, WorldMap, direction, i, ws)
    local success = false
    if direction == "forward" and turtle.forward() then
        success = true
        turtleLib.Sonar(TurtleObject, WorldMap, true, true, true)
        TurtleObject["position"] = TurtleObject["position"]:add(utils.neswudDirectionVectors[TurtleObject["face"]])
    elseif direction == "up" and turtle.up() then
        success = true
        turtleLib.Sonar(TurtleObject, WorldMap, true, true, false)
        TurtleObject["position"] = TurtleObject["position"]:add(utils.neswudDirectionVectors["up"])
    elseif direction == "down" and turtle.down() then
        success = true
        turtleLib.Sonar(TurtleObject, WorldMap, true, false, true)
        TurtleObject["position"] = TurtleObject["position"]:add(utils.neswudDirectionVectors["down"])
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

function turtleLib.MoveToDirection(TurtleObject, WorldMap, targetFace, i, ws)
    local success
    
    if targetFace == "up" then
        success = turtleLib.SafeMove(TurtleObject, WorldMap, "up", i, ws)
    elseif targetFace == "down" then
        success = turtleLib.SafeMove(TurtleObject, WorldMap, "down", i, ws)
    else
        local diff = (utils.FaceToIndex(targetFace) - TurtleObject["faceIndex"]) % 4
        
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
        
        success = turtleLib.SafeMove(TurtleObject, WorldMap, "forward", i, ws)
    end

    return success
end

function turtleLib.MoveToNeighbor(TurtleObject, WorldMap, x, y, z, i, ws)
    local targetV = vector.new(x, y, z)
    local delta = targetV:sub(TurtleObject["position"])
    
    if delta:length() ~= 1 then
        return false
    end
    
    local targetFace = utils.duwsenDirectionVectors[delta:tostring()]

    if not turtleLib.MoveToDirection(TurtleObject, WorldMap, targetFace, i, ws) then
        return false
    end

    return true
end

-- local function intersectionHandle(step, turtleObject, i, ws)
--     repeat
--         local mergePossible = true
--         
--         -- get all intersection entries
--         local intersectionEntries = {}
--         for neighborDirection, neighborDirectionVector in ipairs(utils.neswudDirectionVectors) do
--             if neighborDirection ~= step["direction"] then
--                 table.insert(intersectionEntries, step["vector"]:add(neighborDirectionVector))
--             end
--         end
--         ws.send(textutils.serializeJSON({type = "intersection", payload = intersectionEntries}))
--         local entriesDataKV = utils.listenForWsMessage("intersectionData")
--         
--         -- remove the ones without turtles
--         for vectorKey, entry in pairs(entriesDataKV) do
--             if #entry["turtles"] == 0 then
--                 entriesDataKV[vectorKey] = nil
--             end
--         end
--         
--         -- get all turtles with higher priority
--         local problematicTurtles = {}
--         local currentLocation = turtleObject["journeyPath"][i - 1]
--         for _, entry in pairs(entriesDataKV) do
--             if #entry["turtles"] > #currentLocation["turtles"]
--             or (#entry["turtles"] == #currentLocation["turtles"]
--             and utils.FaceToIndex(entry["direction"]) > utils.FaceToIndex(currentLocation["direction"])) then
--                 for _, turtle in ipairs(entry["turtles"]) do
--                     if not utils.TableContains(problematicTurtles, turtle)
--                     and not utils.TableContains(currentLocation["turtles"], turtle) then
--                         table.insert(problematicTurtles, turtle)
--                     end
--                 end
--             end
--         end
-- 
--         if #problematicTurtles == 0 then 
--             return
--         end
--         
--         local highestDiff = 0
--         for _, problematicTurtle in ipairs(problematicTurtles) do
--             for intersectionIndex, problematicStep in ipairs(problematicTurtle["journeyPath"]) do
--                 if problematicStep["vector"] == step["vector"] then
--                     local diff = intersectionIndex - problematicTurtle["journeyStepIndex"]
--                     if diff <= 3 and diff > highestDiff then                   
--                         highestDiff = diff
--                         mergePossible = false
--                     end
--                 end
--             end
--         end
-- 
--         if not mergePossible then
--             os.sleep(highestDiff)
--         end
-- 
--     until not mergePossible
-- end

local function handleMovement(TurtleObject, WorldMap, step, i, ws)
    if not turtleLib.MoveToDirection(TurtleObject, WorldMap, step, i, ws) then
        print("Failed to move to direction: " .. step["direction"])
        
        for _, passingTurtleID in ipairs(step["turtles"]) do
            ws.send(textutils.serializeJSON({
                type = "PassThrough",
                receiver = passingTurtleID,
                newHeader = "obstacle on your way",
                payload = { roadBlock = TurtleObject["position"]:add(utils.neswudDirectionVectors[step["direction"]]) }
            }))
        end

        return false
    end

    return true
end

local function subJourney(TurtleObject, WorldMap, destination, doAtTheEnd, ws, interruption)
    TurtleObject["busy"] = true
    
    repeat
        local startTime = os.epoch("utc")
        local syncDelay = 0

        -- If journeyPath not yet set, request it from the server
        if not TurtleObject["journeyPath"] then
            ws.send(textutils.serializeJSON({
                type = "Journey",
                payload = {
                    TurtleObject = TurtleObject,
                    destination = destination
                }
            }))

            local message = utils.listenForWsMessage("NewPath")
            local journeyPath = message.payload.journeyPath
            syncDelay = message.payload.timeToWait or 0
            
            if journeyPath == "no path found" then
                print("I am trapped :(")
                TurtleObject["journeyStepIndex"] = nil
                TurtleObject["journeyPath"] = nil
                TurtleObject["busy"] = false
                return false
            end

            if not doAtTheEnd or doAtTheEnd ~= "go" then
                destination = journeyPath[#journeyPath - 1].vector
            end

            TurtleObject["journeyPath"] = journeyPath
            TurtleObject["journeyStepIndex"] = 1

            print("Best path found with " .. #journeyPath .. " steps.")
        end

        local calculationTime = os.epoch("utc") - startTime
        local timeToWait = syncDelay - calculationTime
        if timeToWait > 0 then
            print("Sleeping for " .. timeToWait/1000 .. " seconds before starting the journey.")
            os.sleep(timeToWait)
        end

        -- Follow the current journeyPath
        while TurtleObject["journeyPath"] and TurtleObject["journeyStepIndex"] <= #TurtleObject["journeyPath"] do
            local step = TurtleObject["journeyPath"][TurtleObject["journeyStepIndex"]]
            
            if TurtleObject["journeyStepIndex"] < #TurtleObject["journeyPath"] or step.special.lastBlock == "go" then
                if handleMovement(TurtleObject, WorldMap, step, TurtleObject["journeyStepIndex"], ws) == false then
                    break
                end
            end
            
            if interruption[1] == true then
                interruption[1] = false
                break
            end
            TurtleObject["journeyStepIndex"] = TurtleObject["journeyStepIndex"] + 1
            
        end

        -- Clear after journey finished
        TurtleObject["journeyStepIndex"] = nil
        TurtleObject["journeyPath"] = nil

        ws.send(textutils.serializeJSON({
            type = "Journeys End",
            payload = {
                journeyPath = TurtleObject["journeyPath"], 
                turtleID = TurtleObject["id"]
            }
        }))

    until TurtleObject["position"]:equals(destination)

    TurtleObject["busy"] = false
    utils.SerializeAndSave(TurtleObject, "turtleLog")

    return true
end

local function checkForInterruptions(TurtleObject, WorldMap, destination, doAtTheEnd, ws, interruption)
    while true do
        local message = utils.listenForWsMessages({
            "obstacle on your way",
            "new turtle on your path"
        })

        -- Replace the journey path with the new one from the message
        local newPath = message.payload.newPath
        if newPath and type(newPath) == "table" then
            print("Received new path from server, updating journey...")

            TurtleObject["journeyPath"] = newPath
            TurtleObject["journeyStepIndex"] = 1
        else
            print("Interrupt message received but no valid new path.")
            interruption[1] = true
        end
    end
end

function turtleLib.Journey(TurtleObject, WorldMap, destination, doAtTheEnd, ws)
    local interruption = { false }
    parallel.waitForAny(
        function()
            subJourney(TurtleObject, WorldMap, destination, doAtTheEnd, ws, interruption)
        end,

        function()
            checkForInterruptions(TurtleObject, WorldMap, destination, doAtTheEnd, ws, interruption)
        end
    )
end

return turtleLib