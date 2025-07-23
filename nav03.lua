---@diagnostic disable: undefined-global, undefined-field
local utils = require("utils")

local nav = {}

function nav.UpstreamCalculation(obstacle)
    local directionIndex = utils.FaceToIndex(obstacle["flowDirection"])
    local upstreamIndex = (directionIndex + 2) % 4

    return utils.neswDirections[upstreamIndex]
end

function nav.DirectionCalculation(neighborVector, currentVector)
    return utils.duwsenDirectionVectors[neighborVector:sub(currentVector):tostring()]
end

function nav.aStar(bDirection, bX, bY, bZ, dX, dY, dZ, Obstacles, isReverse)
    local b = vector.new(bX, bY, bZ)
    local d = vector.new(dX, dY, dZ)
    local dKey = d:tostring()
    
    if not Obstacles then
        Obstacles = {}
    end

    local queue = {{
        vector = b,
        weight = utils.ManhattanDistance(b, d),
        stepCount = 0,
        turnCount = 0,
        direction = bDirection
    }}

    setmetatable(queue, utils.Heap)

    local cameFrom = {}  -- key: position string, value: parent node
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

                if not nav.aStar("north", dX, dY, dZ, bX, bY, bZ, Obstacles, true) then
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

            if visited[neighborKey] then
                goto continue
            end
            
            if Obstacles[neighborKey] and not Obstacles[neighborKey]["flowDirection"] then
                goto continue
            end
            
            local node = {
                vector = neighborVector,
                weight = nil,
                stepCount = current["stepCount"] + 1,
                turnCount = current["turnCount"],
                direction = nav.DirectionCalculation(neighborVector, current["vector"])
            }

            local upStream = nav.UpstreamCalculation(Obstacles[neighborKey])
            if node["direction"] == upStream then
                goto continue
            end
            
            if node["direction"] ~= current["direction"] then
                node["turnCount"] = node["turnCount"] + 1
            end
            
            local estimatedDistance = utils.ManhattanDistance(neighborVector, d)
            node["weight"] = estimatedDistance + node["stepCount"] + node["turnCount"]

            visited[neighborKey] = true
            cameFrom[neighborKey] = current

            queue:push(node)
            
            ::continue::
        end
    end

    return false
end


--[[
cameFrom example:
{
    ["(1, 2, 3)"] = { vector = vector.new(1,1,3), ... },
    ["(2, 2, 3)"] = { vector = vector.new(1,2,3), ... },
    ...
}
]]

--[[
queue example (as a heap):
{
    {
        vector = vector.new(1,2,3),
        weight = 7,
        stepCount = 3,
        turnCount = 1
    },
    {
        vector = vector.new(2,2,3),
        weight = 8,
        stepCount = 4,
        turnCount = 1
    },
    ...
}
]]

--[[
visited example:
{
    ["(1, 2, 3)"] = true,
    ["(2, 2, 3)"] = true,
    ...
}
]]

--[[
bestPath example:
{
    { vector = vector.new(1,1,3), ... },
    { vector = vector.new(1,2,3), ... },
    { vector = vector.new(2,2,3), ... },
    ...
}
]]

--testest
return nav