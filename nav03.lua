--@diagnostic disable: undefined-global, undefined-field
local utils = require("utils")

local nav = {}

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

local function unixTimeCalculation(stepCount, turnCount, digCount)
    return os.epoch("utc") + stepCount * 400 + turnCount * 200 + digCount * 500
end

function nav.aStar(config, WorldMap, turtleObject)
    if not WorldMap then
        WorldMap = {}
    end

    ---/*%$# QUEUE INIT #$%*\---
    local queue = {}
    queue[1] = {}
    queue[1]["vector"] = config["beginning"]
    queue[1]["weight"] = utils.MultiManhattanDistance(config["beginning"], config["destinations"])
    queue[1]["stepCount"] = 0
    queue[1]["turnCount"] = 0
    queue[1]["direction"] = config["initialDirection"]
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
            local journeyPath = {}
            local totalTimeToWait = current["timeToWait"] or 0

            local node = current
            while node do
                local journeyStep = {}
                journeyStep["vector"] = node["vector"]
                journeyStep["turtles"] = node["turtles"] or {}

                if turtleObject then
                    journeyStep["turtles"][turtleObject["id"]] = {
                        direction = node["direction"],
                        unixTime = unixTimeCalculation(node["stepCount"], node["turnCount"], node["digCount"]),
                    }
                end

                table.insert(journeyPath, 1, journeyStep)
                node = cameFrom[node["vector"]:tostring()]
            end

            table.remove(journeyPath, 1)
            return {journeyPath, totalTimeToWait}
        end

        ---/*%$# QUEUE BUILD #$%*\---
        if current["stepCount"] * 2 < turtleObject["fuel"] then
            local neighborVectors = utils.getNeighbors(current["vector"])
            
            for _, neighborVector in ipairs(neighborVectors) do
                local neighborKey = neighborVector:tostring()

                -- NEIGHBOR INIT
                local directionKey = neighborVector:sub(current.vector):tostring()
                local neighbor = {
                    turtles = WorldMap[neighborKey] and WorldMap[neighborKey].turtles or {},
                    direction = utils.duwsenDirectionVectors[directionKey],
                    stepCount = current.stepCount + 1,
                    turnCount = current.turnCount or 0,
                    digCount = current.digCount or 0,
                    vector = neighborVector,
                    flowResistance = 0,
                    timeToWait = 0,
                    weight = 0,
                }

                -- BLOCKED NEIGHBOR CHECK
                if WorldMap[neighborKey] and WorldMap[neighborKey]["blocked"] then           
                    if not config["dig"] then
                        goto continue  -- Skip blocked neighbors unless digging is allowed
                    end

                    neighbor["digCount"] = current["digCount"] + 1
                end
                

                -- FLOW
                for _, turtle in pairs(neighbor["turtles"]) do
                    local timeDiff = math.abs(
                        unixTimeCalculation(turtle["stepCount"], 
                                            turtle["turnCount"], 
                                            turtle["digCount"]) - turtle["unixTime"]
                    
                    )

                    if timeDiff < 5000 then
                        neighbor["flowResistance"] = neighbor["flowResistance"] + 10
                        neighbor["timeToWait"] = math.max(neighbor["timeToWait"], timeDiff)
                    end

                    local flow = flowCalculation(turtle["direction"], neighbor["direction"])
                    if flow == "AgainstFlow" then
                        neighbor["flowResistance"] = neighbor["flowResistance"] + 2
                    elseif flow == "PathFlow" then
                        neighbor["flowResistance"] = neighbor["flowResistance"] - 1
                    else
                        neighbor["flowResistance"] = neighbor["flowResistance"] + 1
                    end
                end

                -- TURN
                if not (neighbor["direction"] == "up" or neighbor["direction"] == "down") or
                        current["direction"] == neighbor["direction"] then
                    -------------------------------------------------------
                    local currentDirectionIndex = utils.FaceToIndex(current["direction"])
                    local neighborDirectionIndex = utils.FaceToIndex(neighbor["direction"])

                    local diff = (neighborDirectionIndex - currentDirectionIndex) % 4
                    if diff == 1 or diff == 3 then
                        neighbor["turnCount"] = neighbor["turnCount"] + 1
                    elseif diff == 2 then
                        neighbor["turnCount"] = neighbor["turnCount"] + 2
                    end
                end

                -- WEIGHT
                local estimatedDistance = utils.MultiManhattanDistance(neighborVector, config["destinations"])
                neighbor["weight"] = estimatedDistance + 
                                    neighbor["stepCount"] + 
                                    neighbor["turnCount"] + 
                                    neighbor["flowResistance"]
                ----------------------------------------------
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