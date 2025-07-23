---@diagnostic disable: undefined-global, undefined-field
local utils = require("utils")

local nav = {}

function nav.aStar(bDirection, bX, bY, bZ, dX, dY, dZ, Obstacles)
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
    while #queue > 0 do
        loopCount = loopCount + 1
        if loopCount % 1000 == 0 then
            print("A* loop count: " .. loopCount)

            os.queueEvent("yield")
            os.pullEvent()
        end


        local current = queue:pop()
        local currentKey = current["vector"]:tostring()

        --print("new current: " .. currentKey .. " with weight: " .. current["weight"] .. "direction: " .. current["direction"])

        if currentKey == dKey then

            local bestPath = {}

            while current do
                table.insert(bestPath, 1, current)
                currentKey = current.vector:tostring()
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
            if not visited[neighborKey] and not Obstacles[neighborKey] then
                local toPush = {
                    vector = neighborVector,
                    weight = nil,
                    stepCount = current["stepCount"] + 1,
                    turnCount = current["turnCount"],
                    direction = utils.duwsenDirectionVectors[neighborVector:sub(current["vector"]):tostring()]
                }
                
                if toPush["direction"] ~= current["direction"] then
                    toPush["turnCount"] = toPush["turnCount"] + 1
                end
                
                local estimatedDistance = utils.ManhattanDistance(neighborVector, d)
                toPush["weight"] = estimatedDistance + toPush["stepCount"] + toPush["turnCount"]

                visited[neighborKey] = true
                cameFrom[neighborKey] = current

                queue:push(toPush)
            end
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