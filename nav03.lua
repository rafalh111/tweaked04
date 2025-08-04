---@diagnostic disable: undefined-global, undefined-field
local utils = require("utils")

local nav = {}

local function flowCalculation(obstacle, neighbor)
    local neighborDir = neighbor["direction"]
    local flowDir = obstacle["flowDirection"]

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

function nav.aStar(bDirection, b, d, fuel, WorldMap, turtleID)
    local dKey = d:tostring()
    
    if not WorldMap then
        WorldMap = {}
    end

    local queue = {{
        vector = b,
        weight = utils.ManhattanDistance(b, d),
        stepCount = 0,
        turnCount = 0,
        direction = bDirection
    }}

    setmetatable(queue, utils.Heap)

    local cameFrom = {}  -- key: position string, value: parent neighbor
    local visited = {[b:tostring()] = true}

    local loopCount = 0
    local InitialWeight = utils.ManhattanDistance(b, d) + 0 -- Initial weight is just the Manhattan distance
    local reverseCheck = false

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
            --     print("The destination is unreachable.")
            --     return false
            -- end
            --
            --     reverseCheck = true
            -- end

            os.queueEvent("yield")
            os.pullEvent()
        end

        if currentKey == dKey then
            local bestPath = {}

            while current do
                current["weight"] = nil  -- Remove weight from the path
                current["stepCount"] = nil  -- Remove step count from the path
                current["turnCount"] = nil  -- Remove turn count from the path
                --current["flowDirection"] = current["direction"]  -- Keep the flow direction for the path
                
                if turtleID then
                    current["turtles"] = current["turtles"] or {}
                    table.insert(current["turtles"], turtleID)
                end
                
                table.insert(bestPath, 1, current)
                currentKey = current["vector"]:tostring()
                current = cameFrom[currentKey]
            end

            table.remove(bestPath, 1)
            bestPath[#bestPath]["special"]["lastBlock"] = true

            return bestPath
        end

        local neighborVectors = utils.getNeighbors(current["vector"])

        for _, neighborVector in ipairs(neighborVectors) do
            local neighborKey = neighborVector:tostring()

            -- skip if visited or an obstacle
            if visited[neighborKey] then
                goto continue  
            elseif WorldMap[neighborKey] and not WorldMap[neighborKey]["flowDirection"] then
                goto continue
            end
            
            local neighbor = {}
            neighbor["vector"] = neighborVector
            neighbor["turnCount"] = current["turnCount"]
            neighbor["stepCount"] = current["stepCount"] + 1
            neighbor["direction"] = utils.duwsenDirectionVectors[neighbor["vector"]:sub(current["vector"]):tostring()]

            -- FUEL
            if neighbor["stepCount"] * 2 > fuel then
                goto continue
            end

            -- FLOW
            local flowResistance = 0
            if WorldMap[neighborKey] and WorldMap[neighborKey]["flowDirection"] then
                local flow = flowCalculation(WorldMap[neighborKey], neighbor)
                if flow == "AgainstFlow" then
                    goto continue
                elseif flow == "PathFlow" then
                    flowResistance = flowResistance - 1                
                else
                    flowResistance = flowResistance + 1
                    neighbor["special"]["intersection"] = true
                end
            end

            -- TURN
            local turnCount = neighbor["turnCount"]
            if current["direction"] ~= neighbor["direction"] then
                neighbor["turn"] = true
                turnCount = turnCount + 1
            end

            -- WEIGHT
            local estimatedDistance = utils.ManhattanDistance(neighborVector, d)
            neighbor["weight"] = estimatedDistance + neighbor["stepCount"] + turnCount + flowResistance

            visited[neighborKey] = true
            cameFrom[neighborKey] = current
            queue:push(neighbor)
            
            ::continue::
        end
    end

    return false
end
-- bestPath example look like this: 
-- {
--     {vector = vector.new(1, 0, 0), weight = 3},
--     {vector = vector.new(2, 0, 0), weight = 2},
--     {vector = vector.new(3, 0, 0), weight = 1},
--     {vector = vector.new(4, 0, 0), weight = 0}
-- }

return nav