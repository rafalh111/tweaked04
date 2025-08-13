--@diagnostic disable: undefined-global, undefined-field
local utils = require("utils")

local nav = {}

local function flowCalculation(obstacle, neighbor)
    local neighborDir = neighbor["direction"]
    local flowDir = obstacle["direction"]

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
end

function nav.aStar(config, WorldMap, turtleObject)
    if not WorldMap then
        WorldMap = {}
    end

    local queue = {}
    queue[1]["vector"] = config["beginning"]
    queue[1]["weight"] = utils.MultiManhattanDistance(config["beginning"], config["destinations"])
    queue[1]["stepCount"] = 0
    queue[1]["turnCount"] = 0
    queue[1]["direction"] = config["initialDirection"]
    setmetatable(queue, utils.Heap)

    local cameFrom = {}  -- key: position string, value: parent neighbor
    local visited = {[config["beginning"]:tostring()] = true}

    local loopCount = 0

    while #queue > 0 do
        loopCount = loopCount + 1

        local current = queue:pop()
        local currentKey = current["vector"]:tostring()

        if loopCount % 1000 == 0 then
            print("A* loop count: " .. loopCount)
            
            -- if not reverseCheck and current["weight"] > InitialWeight * 2 then
            --     if isReverse then
            --         return false
            --     end
            --
            -- if not nav.aStar("north", d, b, WorldMap, true) then
            --     print("The destinations is unreachable.")
            --     return false
            -- end
            --
            --     reverseCheck = true
            -- end

            os.queueEvent("yield")
            os.pullEvent()
        end
        
        -- PATH RECONSTRUCTION
        if isDestination(config["destinations"], currentKey) then
            local journeyPath = {}

            while current do
                current["weight"] = nil  -- Remove weight from the path

                if turtleObject then
                    current["turtles"] = current["turtles"] or {}
                    table.insert(current["turtles"], turtleObject["id"])
                end
                
                table.insert(journeyPath, 1, current)
                currentKey = current["vector"]:tostring()
                current = cameFrom[currentKey]
            end

            table.remove(journeyPath, 1)
            journeyPath[#journeyPath]["special"]["lastBlock"] = true

            return journeyPath
        end

        -- QUEUE BUILD
        if current["stepCount"] * 2 < turtleObject["fuel"] then
            local neighborVectors = utils.getNeighbors(current["vector"])
            
            for _, neighborVector in ipairs(neighborVectors) do
                local neighborKey = neighborVector:tostring()

                -- skip if visited or an obstacle
                if visited[neighborKey] then
                    goto continue
                elseif WorldMap[neighborKey] and not WorldMap[neighborKey]["direction"] then
                    goto continue
                end
                
                local neighbor = {}
                neighbor["vector"] = neighborVector
                neighbor["turnCount"] = current["turnCount"]
                neighbor["stepCount"] = current["stepCount"] + 1
                neighbor["direction"] = utils.duwsenDirectionVectors[neighbor["vector"]:sub(current["vector"]):tostring()]

                -- FLOW
                local flowResistance = 0
                if WorldMap[neighborKey] and WorldMap[neighborKey]["direction"] then
                    local flow = flowCalculation(WorldMap[neighborKey], neighbor)
                    if flow == "AgainstFlow" then
                        goto continue
                    elseif flow == "PathFlow" then
                        flowResistance = flowResistance - 1                
                    else
                        flowResistance = flowResistance + 1
                    end
                end

                -- TURN
                local turnCount = neighbor["turnCount"]
                if current["direction"] ~= neighbor["direction"] then
                    turnCount = turnCount + 1
                end

                -- WEIGHT
                local estimatedDistance = utils.MultiManhattanDistance(neighborVector, config["destinations"])
                neighbor["weight"] = estimatedDistance + neighbor["stepCount"] + turnCount + flowResistance

                visited[neighborKey] = true
                cameFrom[neighborKey] = current
                queue:push(neighbor)
                
                ::continue::
            end
        end
    end

    return false
end

return nav