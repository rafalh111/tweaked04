--@diagnostic disable: undefined-global, undefined-field
local nav = require("nav03")
local utils = require("utils")
local textutils
local os
local rednet
local parallel

local turtleLib = {}

function turtleLib.LoadTurtleState(ws)
    local realTurtle = {}   -- this will hold actual data
    local turtleLog = utils.ReadAndUnserialize("turtleLog")

    -- TurtleObject table that user code will interact with
    local TurtleObject = {}
    setmetatable(TurtleObject, {
        __index = realTurtle, -- read from real state
        __newindex = function(_, key, value)
            realTurtle[key] = value  -- update real state
            utils.SerializeAndSave(realTurtle, "turtleLog") -- auto-save
        end
    })

    if turtleLog then
        for k, v in pairs(turtleLog) do
            realTurtle[k] = v
        end
        realTurtle["position"] = vector.new(
            realTurtle["position"].x,
            realTurtle["position"].y,
            realTurtle["position"].z
        )
    else
        rednet.send(realTurtle["baseID"], realTurtle, "TurtleBorn")
        local senderID, message, protocol = rednet.receive()
        if protocol == "Completion1" then
            message = textutils.unserialize(message)
            for k, v in pairs(message) do
                realTurtle[k] = v
            end
        end

        ws.send(textutils.serializeJSON({type = "turtleBorn", payload = realTurtle}))
        local event, p1, p2, p3 = os.pullEvent()
        message = textutils.unserializeJSON(p2)
        if message.type == "Completion2" then
            for k, v in pairs(message.payload) do
                realTurtle[k] = v
            end
        end

        utils.SerializeAndSave(realTurtle, "turtleLog")
    end

    return TurtleObject -- always return TurtleObject
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

    
end

function turtleLib.SafeMove(TurtleObject, WorldMap, direction, i, ws)
    local actionTable = {}
    actionTable["forward"] = function()
        if not turtle.detect() then
            turtle.forward()
            TurtleObject["position"] = TurtleObject["position"]:add(utils.neswudDirectionVectors[TurtleObject["face"]])

            if i then
                TurtleObject["journeyStepIndex"] = i
            end

            turtleLib.Sonar(TurtleObject, WorldMap, true, true, true, ws)
            
            return true
        else
            return false
        end
    end

    actionTable["up"] = function()
        if not turtle.detectUp() then
            turtle.up()
            TurtleObject["position"] = TurtleObject["position"]:add(utils.neswudDirectionVectors["up"])

            if i then
                TurtleObject["journeyStepIndex"] = i
            end

            turtleLib.Sonar(TurtleObject, WorldMap, true, true, false, ws)
            
            return true
        else
            return false
        end
    end

    actionTable["down"] = function()
        if not turtle.detectDown() then
            turtle.down()
            TurtleObject["position"] = TurtleObject["position"]:add(utils.neswudDirectionVectors["down"])

            if i then
                TurtleObject["journeyStepIndex"] = i
            end

            turtleLib.Sonar(TurtleObject, WorldMap, true, false, true, ws)
            
            return true
        else
            return false
        end
    end
    
    actionTable["left"] = function()
        turtle.turnLeft()
        TurtleObject["faceIndex"] = (TurtleObject["faceIndex"] - 2) % 4 + 1
        TurtleObject["face"] = utils.neswDirections[TurtleObject["faceIndex"]]
        actionTable["forward"]()
    end

    actionTable["right"] = function()
        turtle.turnRight()
        TurtleObject["faceIndex"] = TurtleObject["faceIndex"] % 4 + 1
        TurtleObject["face"] = utils.neswDirections[TurtleObject["faceIndex"]]
        actionTable["forward"]()
    end

    actionTable["backward"] = function()
        if math.random(1, 2) == 1 then
            for i = 1, 2 do
                turtle.turnLeft()
                TurtleObject["faceIndex"] = (TurtleObject["faceIndex"] - 2) % 4 + 1
                turtleLib.Sonar(TurtleObject, WorldMap, true, false, false, ws)
            end
        else
            for i = 1, 2 do
                turtle.turnRight()
                TurtleObject["faceIndex"] = TurtleObject["faceIndex"] % 4 + 1
                turtleLib.Sonar(TurtleObject, WorldMap, true, false, false, ws)
            end
        end
    end
end

function turtleLib.MoveToDirection(TurtleObject, WorldMap, neswudDirection, i, ws)
    local flrDirection = utils.neswudToFlrud(neswudDirection)
    return turtleLib.SafeMove(TurtleObject, WorldMap, flrDirection, i, ws)
end

function turtleLib.MoveToNeighbor(TurtleObject, WorldMap, x, y, z, i, ws)
    local targetV = vector.new(x, y, z)
    local delta = targetV:sub(TurtleObject["position"])
    
    if delta:length() ~= 1 then
        return false
    end
    
    local neswudDirection = utils.duwsenDirectionVectors[delta:tostring()]

    if not turtleLib.MoveToDirection(TurtleObject, WorldMap, neswudDirection, i, ws) then
        return false
    end

    return true
end

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

local function subJourney(TurtleObject, WorldMap, destinations, doAtTheEnd, ws, interruption)
    repeat
        local closestDestination = vector.new()
        -- local syncDelay = 0

        -- If journeyPath not yet set, request it from the server
        if not TurtleObject["journeyPath"] then
            ws.send(textutils.serializeJSON({
                type = "Journey",
                payload = {
                    TurtleObject = TurtleObject,
                    destinations = destinations,
                    doAtTheEnd = doAtTheEnd,
                    sendTime = os.epoch()
                }
            }))

            local message = utils.listenForWsMessage("NewPath")
            local journeyPath = message.payload.journeyPath

            if message.payload == "no path found" then
                print("I am trapped :(")
                TurtleObject["journeyStepIndex"] = nil
                TurtleObject["journeyPath"] = nil
                return false
            end

            if doAtTheEnd ~= "go" then
                table.remove(journeyPath, #journeyPath) -- Remove the last step if it's not "go"
            end
            closestDestination = journeyPath[#journeyPath].vector

            TurtleObject["journeyPath"] = journeyPath
            TurtleObject["journeyStepIndex"] = 1

            print("Best path found with " .. #journeyPath .. " steps.")
        end
        
        -- Follow the current journeyPath
        while TurtleObject["journeyPath"] and TurtleObject["journeyStepIndex"] <= #TurtleObject["journeyPath"] do
            local step = TurtleObject["journeyPath"][TurtleObject["journeyStepIndex"]]

            os.sleep(step["syncDelay"]/1000)

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

    until TurtleObject["position"]:equals(closestDestination)

    return true
end

local function checkForInterruptions(TurtleObject, WorldMap, destinations, doAtTheEnd, ws, interruption)
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

function turtleLib.Journey(TurtleObject, WorldMap, destinations, doAtTheEnd, ws)
    local interruption = { false }
    parallel.waitForAny(
        function()
            subJourney(TurtleObject, WorldMap, destinations, doAtTheEnd, ws, interruption)
        end,

        function()
            checkForInterruptions(TurtleObject, WorldMap, destinations, doAtTheEnd, ws, interruption)
        end
    )
end

return turtleLib