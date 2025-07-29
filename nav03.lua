---@diagnostic disable: undefined-global, undefined-field
local utils = require("utils")

local nav = {}

function nav.FlowCalculation(obstacle, neighbor)
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

function nav.DirectionCalculation(neighborVector, currentVector)
    return utils.duwsenDirectionVectors[neighborVector:sub(currentVector):tostring()]
end

function nav.aStar(bDirection, bX, bY, bZ, dX, dY, dZ, WorldMap, isReverse, turtleID)
    local b = vector.new(bX, bY, bZ)
    local d = vector.new(dX, dY, dZ)
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
            
            if not reverseCheck and current["weight"] > InitialWeight * 2 then
                if isReverse then
                    return false
                end

                if not nav.aStar("north", dX, dY, dZ, bX, bY, bZ, WorldMap, true) then
                    print("The destination is unreachable.")
                    return false
                end

                reverseCheck = true
            end

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

            return bestPath
        end

        local neighborVectors = {
            current["vector"]:add(vector.new(1, 0, 0)),
            current["vector"]:add(vector.new(-1, 0, 0)),
            current["vector"]:add(vector.new(0, 0, 1)),
            current["vector"]:add(vector.new(0, 0, -1)),
            current["vector"]:add(vector.new(0, 1, 0)),
            current["vector"]:add(vector.new(0, -1, 0))
        }

        for _, neighborVector in ipairs(neighborVectors) do
            local neighborKey = neighborVector:tostring()

            -- skip if visited or an obstacle
            if visited[neighborKey] then
                goto continue  
            elseif WorldMap[neighborKey] and not WorldMap[neighborKey]["flowDirection"] then
                goto continue
            end
            
            local neighbor = {
                vector = neighborVector,
                turnCount = current["turnCount"],
                stepCount = current["stepCount"] + 1,
                direction = nav.DirectionCalculation(neighborVector, current["vector"])
            }

            -- flow checks
            local flowResistance = 0
            if WorldMap[neighborKey] and WorldMap[neighborKey]["flowDirection"] then
                local flow = nav.FlowCalculation(WorldMap[neighborKey], neighbor)
                if flow == "AgainstFlow" then
                    goto continue
                elseif flow == "MergeFromSide" then
                    flowResistance = flowResistance + 1
                elseif flow == "PathFlow" then
                    flowResistance = flowResistance - 1
                end
            end

            -- turn penalty
            local turnCount = neighbor["turnCount"]
            if current["direction"] ~= neighbor["direction"] then
                turnCount = turnCount + 1
            end

            -- final weight
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