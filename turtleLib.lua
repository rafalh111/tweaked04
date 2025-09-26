-- turtleLib.lua (fixed & cleaned)
local nav = require("nav03")
local utils = require("utils")
-- don't shadow globals like textutils/os by declaring them as nil locals

local turtleLib = {}

-- Helper: returns index (number) of matching block in placeOnTheMap.blocks,
-- or false if not found. placeOnTheMap may be nil.
local function blockIsOnTheMap(dataOfTheBlock, placeOnTheMap)
    if not placeOnTheMap or type(placeOnTheMap) ~= "table" then
        return false
    end

    local blocks = placeOnTheMap["blocks"]
    if type(blocks) ~= "table" then
        return false
    end

    local now = os.epoch()
    for blockIndex, block in ipairs(blocks) do
        -- safe comparisons: block.placeTime/removeTime may be nil
        local placeTime = block.placeTime or -math.huge
        local removeTime = block.removeTime or math.huge

        -- block is considered present if placeTime <= now < removeTime
        if placeTime <= now and now < removeTime and dataOfTheBlock == block.data then
            return blockIndex
        end
    end

    return false
end

function turtleLib.LoadTurtleState(ws, defaultTurtle)
    local turtleLog = utils.ReadAndUnserialize("turtleLog")
    local realTurtle = defaultTurtle or {}   -- this will hold actual data
    local TurtleObject = {}

    -- TurtleObject table that user code will interact with
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
        if realTurtle["position"] and realTurtle["position"].x then
            realTurtle["position"] = vector.new(
                realTurtle["position"].x,
                realTurtle["position"].y,
                realTurtle["position"].z
            )
        end
    end

    if ws then
        ws.send(textutils.serializeJSON({type = "turtleBorn", payload = realTurtle}))
    end

    return TurtleObject -- always return TurtleObject
end

function turtleLib.Sonar(TurtleObject, LocalMap, InFront, Above, Below, ws)
    local detectedChanges = {}

    if InFront then
        local vectorKey = TurtleObject["position"]:add(utils.neswudDirectionVectors[TurtleObject["face"]]):tostring()
        local blocked, data = turtle.inspect()
        local dataName = data and data.name or nil
        detectedChanges[vectorKey] = {blocked = blocked, data = dataName}
    end

    if Above then
        local vectorKey = TurtleObject["position"]:add(utils.neswudDirectionVectors["up"]):tostring()
        local blocked, data = turtle.inspectUp()
        local dataName = data and data.name or nil
        detectedChanges[vectorKey] = {blocked = blocked, data = dataName}
    end

    if Below then
        local vectorKey = TurtleObject["position"]:add(utils.neswudDirectionVectors["down"]):tostring()
        local blocked, data = turtle.inspectDown()
        local dataName = data and data.name or nil
        detectedChanges[vectorKey] = {blocked = blocked, data = dataName}
    end

    if LocalMap then
        for vectorKey, inspectVariables in pairs(detectedChanges) do
            local placeEntry = LocalMap[vectorKey]
            local blockReferenceIndex = blockIsOnTheMap(inspectVariables["data"], placeEntry)
            if inspectVariables["blocked"] and not blockReferenceIndex then
                if not LocalMap[vectorKey] then
                    LocalMap[vectorKey] = {blocks = {}}
                end

                table.insert(LocalMap[vectorKey]["blocks"], {
                    data = inspectVariables["data"],
                    placeTime = os.epoch(),
                    removeTime = nil,
                    detectionTime = os.epoch()
                })
            elseif not inspectVariables["blocked"] and blockReferenceIndex then
                -- remove that specific block entry
                table.remove(LocalMap[vectorKey]["blocks"], blockReferenceIndex)

                -- if table empty, clear it (avoid holes)
                if #LocalMap[vectorKey]["blocks"] == 0 then
                    LocalMap[vectorKey]["blocks"] = nil
                end
            end
        end
    end

    if ws then
        ws.send(textutils.serializeJSON({
            type = "MapUpdate",
            payload = detectedChanges
        }))
    end
end

function turtleLib.SafeMove(TurtleObject, LocalMap, direction, ws)
    -- Returns true on successful move; false otherwise.
    local actionTable = {}

    actionTable["forward"] = function()
        if not turtle.detect() then
            local ok, err = turtle.forward()
            if not ok then return false end

            TurtleObject["position"] = TurtleObject["position"]:add(utils.neswudDirectionVectors[TurtleObject["face"]])
            turtleLib.Sonar(TurtleObject, LocalMap, true, true, true, ws)
            return true
        else
            return false
        end
    end

    actionTable["up"] = function()
        if not turtle.detectUp() then
            local ok, err = turtle.up()
            if not ok then return false end

            TurtleObject["position"] = TurtleObject["position"]:add(utils.neswudDirectionVectors["up"])
            turtleLib.Sonar(TurtleObject, LocalMap, true, true, false, ws)
            return true
        else
            return false
        end
    end

    actionTable["down"] = function()
        if not turtle.detectDown() then
            local ok, err = turtle.down()
            if not ok then return false end

            TurtleObject["position"] = TurtleObject["position"]:add(utils.neswudDirectionVectors["down"])
            turtleLib.Sonar(TurtleObject, LocalMap, true, false, true, ws)
            return true
        else
            return false
        end
    end

    actionTable["left"] = function()
        turtle.turnLeft()
        local faceIndex = utils.neswDirections[TurtleObject["face"]]
        faceIndex = (faceIndex - 2) % 4 + 1
        TurtleObject["face"] = utils.neswDirections[faceIndex]
        -- return forward result (so callers can check)
        return actionTable["forward"]()
    end

    actionTable["right"] = function()
        turtle.turnRight()
        local faceIndex = utils.neswDirections[TurtleObject["face"]]
        faceIndex = faceIndex % 4 + 1
        TurtleObject["face"] = utils.neswDirections[faceIndex]
        return actionTable["forward"]()
    end

    actionTable["backward"] = function()
        if math.random(1, 2) == 1 then
            for i = 1, 2 do
                turtle.turnLeft()
                local faceIndex = utils.neswDirections[TurtleObject["face"]]
                faceIndex = (faceIndex - 2) % 4 + 1
                TurtleObject["face"] = utils.neswDirections[faceIndex]
                turtleLib.Sonar(TurtleObject, LocalMap, true, false, false, ws)
            end
        else
            for i = 1, 2 do
                turtle.turnRight()
                local faceIndex = utils.neswDirections[TurtleObject["face"]]
                faceIndex = (faceIndex % 4) + 1
                TurtleObject["face"] = utils.neswDirections[faceIndex]
                turtleLib.Sonar(TurtleObject, LocalMap, true, false, false, ws)
            end
        end

        return actionTable["forward"]()
    end


    local fn = actionTable[direction]
    if not fn then
        error("Unknown direction for SafeMove: " .. tostring(direction))
    end
    return fn()
end

function turtleLib.MoveToDirection(TurtleObject, LocalMap, neswudDirection, i, ws)
    local flrDirection = utils.neswudToFlrud(neswudDirection)
    return turtleLib.SafeMove(TurtleObject, LocalMap, flrDirection, ws)
end

-- subJourney now correctly calls SafeMove with TurtleObject as first param.
local function subJourney(TurtleObject, LocalMap, destinations, ws, interruption)
    while true do
        -- If journeyPath not yet set, request it from the server
        if not TurtleObject["journeyPath"] then
            if ws then
                ws.send(textutils.serializeJSON({
                    type = "Journey",
                    payload = {
                        TurtleObject = TurtleObject,
                        destinations = destinations,
                        sendTime = os.epoch()
                    }
                }))
            end

            local message = utils.listenForWsMessage("NewPath")
            if not message or message.payload == "no path found" then
                print("I am trapped :(")
                TurtleObject["journeyStepIndex"] = nil
                TurtleObject["journeyPath"] = nil
                return false
            end

            TurtleObject["journeyPath"] = message.payload.journeyPath
            TurtleObject["journeyStepIndex"] = 1

            print("Best path found with " .. (#TurtleObject["journeyPath"] or 0) .. " steps.")
        end

        -- Follow the current journeyPath
        while TurtleObject["journeyPath"] and TurtleObject["journeyStepIndex"] <= #TurtleObject["journeyPath"] do
            local step = TurtleObject["journeyPath"][TurtleObject["journeyStepIndex"]]
            if not step then break end

            os.sleep((step["waitTime"] or 0)/1000)

            -- guard for step.special
            local lastBlockIsGo = false
            if step.special and step.special.lastBlock == "go" then
                lastBlockIsGo = true
            end

            -- SafeMove expects TurtleObject first
            local success = turtleLib.SafeMove(TurtleObject, LocalMap, step["frbludDirection"], ws)
            if not success then
                -- break to request new path
                break
            end

            if interruption[1] == true then
                interruption[1] = false
                break
            end

            TurtleObject["journeyStepIndex"] = TurtleObject["journeyStepIndex"] + 1
        end

        -- Clear after journey finished
        local finishedPath = TurtleObject["journeyPath"]
        TurtleObject["journeyStepIndex"] = nil
        TurtleObject["journeyPath"] = nil

        if ws then
            ws.send(textutils.serializeJSON({
                type = "Journeys End",
                payload = {
                    journeyPath = finishedPath,
                    turtleID = TurtleObject["id"]
                }
            }))
        end

        -- If we did have a finished path and its last element contains a vector, compare position
        if
            finishedPath and #finishedPath > 0 and
            finishedPath[#finishedPath].vector and
            TurtleObject.position:equals(finishedPath[#finishedPath].vector) 
        then
            break
        end
    end

    return true
end

local function checkForInterruptions(TurtleObject, interruption)
    while true do
        local message = utils.listenForWsMessages({
            "obstacle on your way",
            "new turtle on your path"
        })

        if not message then
            sleep(0.1)
            goto continue
        end

        -- Replace the journey path with the new one from the message
        local newPath = message.payload and message.payload.newPath or nil
        if newPath and type(newPath) == "table" then
            print("Received new path from server, updating journey...")
            TurtleObject["journeyPath"] = newPath
            TurtleObject["journeyStepIndex"] = 1
        else
            print("Interrupt message received but no valid new path.")
            interruption[1] = true
        end

        ::continue::
    end
end

function turtleLib.Journey(TurtleObject, LocalMap, destinations, ws)
    local interruption = { false }
    parallel.waitForAny(
        function()
            subJourney(TurtleObject, LocalMap, destinations, ws, interruption)
        end,

        function()
            checkForInterruptions(TurtleObject, interruption)
        end
    )
end

return turtleLib
