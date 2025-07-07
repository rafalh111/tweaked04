---@diagnostic disable: undefined-global, undefined-field
local utils = require("utils")

local nav = {}

function nav.aStar(beginningX, beginningY, beginningZ, destinationX, destinationY, destinationZ)
    local beginning = vector.new(beginningX, beginningY, beginningZ)
    local destination = vector.new(destinationX, destinationY, destinationZ)
    local destinationKey = destination:tostring()

    local queue = {{
        vector = beginning,
        weight = utils.ManhattanDistance(beginning, destination),
        stepCount = 0,
        turnCount = 0
    }}

    setmetatable(queue, utils.Heap)

    local cameFrom = {}  -- key: position string, value: parent node
    local visited = {[beginning:tostring()] = true}
    local Obstacles = utils.ReadAndUnserialize("map") or {}

    local loopCount = 0
    while #queue > 0 do
        loopCount = loopCount + 1
        if loopCount % 100 == 0 then
            os.queueEvent("yield")
            os.pullEvent()
        end

        local current = queue:pop()
        local currentKey = current["vector"]:tostring()

        if currentKey == destinationKey then

            local bestPath = {}

            while current do
                table.insert(bestPath, 1, current)
                currentKey = current.vector:tostring()
                current = cameFrom[currentKey]
            end

            table.remove(bestPath, 1)   

            return bestPath
        end

        local neighbors = {
            current["vector"]:add(vector.new(1, 0, 0)),
            current["vector"]:add(vector.new(-1, 0, 0)),
            current["vector"]:add(vector.new(0, 0, 1)),
            current["vector"]:add(vector.new(0, 0, -1)),
            current["vector"]:add(vector.new(0, 1, 0)),
            current["vector"]:add(vector.new(0, -1, 0))
        }

        for _, neighbor in ipairs(neighbors) do
            local neighborKey = neighbor:tostring()
            if not visited[neighborKey] and not Obstacles[neighborKey] then
                local estimatedDistance = utils.ManhattanDistance(neighbor, destination)

                local turnsSoFar = current["turnCount"]
                if loopCount > 1 and not (neighbor:sub(current["vector"]):equals(current["vector"]:sub(cameFrom[currentKey]["vector"]))) then
                    turnsSoFar = turnsSoFar + 1
                end

                local stepsSoFar = current["stepCount"] + 1
                local weight = estimatedDistance + stepsSoFar + turnsSoFar

                visited[neighborKey] = true
                cameFrom[neighborKey] = current

                queue:push({
                    vector = neighbor,
                    weight = weight,
                    stepCount = stepsSoFar,
                    turnCount = turnsSoFar
                })
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

return nav