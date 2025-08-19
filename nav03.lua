--@diagnostic disable: undefined-global, undefined-field
local utils = require("utils")

local nav = {}

StepTime = 400
TurnTime = 400
DigTime = 500

local function flowCalculation(flowDir, neighborDir)
    -- Perfect alignment with flow
    if neighborDir == flowDir then
        return "PathFlow"
    end

    if neighborDir == "up" or neighborDir == "down" or 
       flowDir == "up" or flowDir == "down" then   

        if (neighborDir == "up" and flowDir == "down") or
        (neighborDir == "down" and flowDir == "up") then
            return "AgainstFlow"
        end
    else
        -- Horizontal flow conflict
        local obstacleFlowIndex = utils.FaceToIndex(flowDir)
        local neighborFlowIndex = utils.FaceToIndex(neighborDir)
        if obstacleFlowIndex and neighborFlowIndex then
            local diff = (obstacleFlowIndex - neighborFlowIndex) % 4
            if diff == 2 then
                return "AgainstFlow"
            end
        end
    end

    return "MergeFromSide"
end

local function isDestination(destinations, currentKey)
    for _, destination in ipairs(destinations) do
        if destination:tostring() == currentKey then
            return true
        end
    end

    return false
end

function nav.aStar(config, WorldMap, turtleObject)
    if not WorldMap then
        WorldMap = {}
    end

    ---/*%$# QUEUE INIT #$%*\---
    local queue = {}
    
    queue[1] = {
        vector = config["beginning"],
        direction = config["initialDirection"],
        stepCount = 0,
        turnCount = 0,
        unixArriveTime = os.epoch("utc"),
        weight = utils.MultiManhattanDistance(config["beginning"], config["destinations"]),
        turtles = WorldMap[config["beginning"]]["turtles"] or {},
        syncDelay = 0
    }

    setmetatable(queue, utils.Heap)

    local cameFrom = {}  -- key: position string, value: parent neighbor
    local bestCost = {[queue[1]["vector"]:tostring()] = queue[1]["weight"]}

    local loopCount = 0

    while #queue > 0 do
        loopCount = loopCount + 1

        local current = queue:pop()
        local currentKey = current["vector"]:tostring()

        local InitialWeight = utils.MultiManhattanDistance(current["vector"], config["destinations"])
        if loopCount % 1000 == 0 then
            print("A* loop count: " .. loopCount)

            if loopCount % 100000 == 0 then
                if not config["reverseCheck"] and current["weight"] > InitialWeight * 2 and
                   not config["dig"] then
                   -----------------------
                    if config["isReverse"] then
                        return false
                    end
                    
                    local reachable = false
                    for _, destination in ipairs(config["destinations"]) do
                        local reverseConfig = {
                            beginning = destination,
                            destinations = config["beginning"],
                            initialDirection = utils.oppositeDirection(current["direction"]),
                            isReverse = true,
                            reverseCheck = true
                        }

                        if nav.aStar(reverseConfig, WorldMap, turtleObject) then
                            reachable = true
                            break
                        end
                    end

                    if not reachable then
                        print("The destinations is unreachable.")
                        return false
                    end
                    
                    config["reverseCheck"] = true
                end
            end

            os.queueEvent("yield")
            os.pullEvent()
        end
        
        ---/*%$# PATH RECONSTRUCTION #$%*\---
        if isDestination(config["destinations"], currentKey) then
            local totalSyncDelay = current["syncDelay"] or 0
            local journeyPath = {}

            while current do
                local journeyStep = {}
                journeyStep["vector"] = current["vector"]
                journeyStep["direction"] = current["direction"]
                journeyStep["turtles"] = current["turtles"] or {}

                if turtleObject then
                    journeyStep["turtles"][turtleObject["id"]] = {
                        direction = current["direction"],
                        unixArriveTime = current["unixArriveTime"],
                        unixLeaveTime = journeyPath[1]["turtles"][turtleObject["id"]]["unixArriveTime"] or nil
                    }
                end
                
                table.insert(journeyPath, 1, journeyStep)
                current = cameFrom[current["vector"]:tostring()]
            end

            if turtleObject and config.doAtTheEnd and not utils.TableContains(config.doAtTheEnd, "go") then
                journeyPath[#journeyPath - 1]["turtles"][turtleObject["id"]]["unixArriveTime"] = nil
            end

            table.remove(journeyPath, 1)
            return {journeyPath = journeyPath, totalSyncDelay = totalSyncDelay}
        end

        ---/*%$# QUEUE BUILD #$%*\---
        if current["stepCount"] * 2 < turtleObject["fuel"] then
            local neighborVectors = utils.getNeighbors(current["vector"])
            
            for _, neighborVector in ipairs(neighborVectors) do
                local neighborKey = neighborVector:tostring()

                -- NEIGHBOR INIT
                local directionKey = neighborVector:sub(current.vector):tostring()
                local neighbor = {
                    vector = neighborVector,
                    direction = utils["duwsenDirectionVectors"][directionKey],
                    stepCount = current["stepCount"] + 1,
                    turnCount = current["turnCount"],
                    unixArriveTime = current["unixArriveTime"] + StepTime,
                    weight = current["weight"] + utils.MultiManhattanDistance(neighborVector, config["destinations"]) + 1,
                    turtles = WorldMap[neighborKey] and WorldMap[neighborKey].turtles or {},
                    syncDelay = current["syncDelay"]
                }

                -- BLOCKED NEIGHBOR CHECK
                if WorldMap[neighborKey] and WorldMap[neighborKey]["blocked"] then           
                    if not config["dig"] then
                        goto continue  -- Skip blocked neighbors unless digging is allowed
                    end

                    neighbor["weight"] = neighbor["weight"] + 100
                    neighbor["unixArriveTime"] = neighbor["unixArriveTime"] + DigTime
                end

                -- TURN
                if not (neighbor["direction"] == "up" or neighbor["direction"] == "down") or
                        current["direction"] == neighbor["direction"] then
                    -------------------------------------------------------
                    local currentDirectionIndex = utils.FaceToIndex(current["direction"])
                    local neighborDirectionIndex = utils.FaceToIndex(neighbor["direction"])

                    local diff = (neighborDirectionIndex - currentDirectionIndex) % 4
                    if diff == 1 or diff == 3 then
                        neighbor["unixArriveTime"] = neighbor["unixArriveTime"] + TurnTime
                        neighbor["turnCount"] = neighbor["turnCount"] + 1
                        neighbor["weight"] = neighbor["weight"] + 1
                    elseif diff == 2 then
                        neighbor["unixArriveTime"] = neighbor["unixArriveTime"] + TurnTime * 2
                        neighbor["turnCount"] = neighbor["turnCount"] + 2
                        neighbor["weight"] = neighbor["weight"] + 2
                    end
                end

                -- FLOW
                for _, turtle in pairs(neighbor["turtles"]) do
                    local flow = flowCalculation(turtle["direction"], neighbor["direction"])
                    if flow == "PathFlow" then
                        neighbor["weight"] = neighbor["weight"] - 1
                    elseif flow == "MergeFromSide" then
                        neighbor["weight"] = neighbor["weight"] + 1
                    elseif flow == "AgainstFlow" then
                        neighbor["weight"] = neighbor["weight"] + 2
                    end
                    
                    if neighbor["unixArriveTime"] >= turtle["unixArriveTime"] then 
                        if neighbor["unixArriveTime"] <= turtle["unixLeaveTime"] then
                            local syncDelay = turtle["unixLeaveTime"] - neighbor["unixArriveTime"] + 200
                            neighbor["weight"] = neighbor["weight"] + 10
                            neighbor["syncDelay"] = neighbor["syncDelay"] + syncDelay
                            neighbor["unixArriveTime"] = neighbor["unixArriveTime"] + syncDelay
                        elseif turtle["unixLeaveTime"] == nil then
                            neighbor["weight"] = neighbor["weight"] + 100
                        end
                    end

                end


                if neighbor["weight"] >= (bestCost[neighborKey] or math.huge) then
                    goto continue  -- This path is not better than what we already have
                end

                bestCost[neighborKey] = neighbor["weight"]
                cameFrom[neighborKey] = current
                queue:push(neighbor)
                
                ::continue::
            end
        end
    end

    return false
end

return nav