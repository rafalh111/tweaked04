---@diagnostic disable: undefined-global, undefined-field

local utils = {}

utils.neswDirections = {"north", "east","south", "west"}

function utils.FaceToIndex(face)
    for index, direction in ipairs(utils.neswDirections) do
        if direction == face then
            return index
        end
    end
end

utils.neswudDirectionVectors = {
    ["north"] = vector.new(0, 0, -1), -- north
    ["east"] = vector.new(1, 0, 0),   -- east
    ["south"] = vector.new(0, 0, 1),  -- south
    ["west"] = vector.new(-1, 0, 0),  -- west
    ["up"] = vector.new(0, 1, 0),     -- up
    ["down"] = vector.new(0, -1, 0)   -- down
}

utils.duwsenDirectionVectors = {
    [vector.new(0, 0, -1):tostring()] = "north",
    [vector.new(1, 0, 0):tostring()] = "east",
    [vector.new(0, 0, 1):tostring()] = "south",
    [vector.new(-1, 0, 0):tostring()] = "west",
    [vector.new(0, 1, 0):tostring()] = "up",
    [vector.new(0, -1, 0):tostring()] = "down"
}

function utils.listenForWsMessage(searchedFor)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "websocket_message" then
            local message = textutils.unserializeJSON(p2)

            if message.type == searchedFor then
                return message
            end
        end
    end 
end

function utils.TableContains(tbl, element)
    for _, v in ipairs(tbl) do
        if utils.CompareVectors(v, element) then
            return true
        end
    end
    
    return false
end

function utils.TableAppend(table1, table2)
    for _, v in ipairs(table2) do
        table.insert(table1, v)
    end
end

function utils.TableCount(t)
    local count = 0

    for index, value in ipairs(t) do
        count = count + 1
    end

    return count
end

function utils.StrToVec(s)
    local x, y, z = s:match("%((%-?%d+), (%-?%d+), (%-?%d+)%)")
    return vector.new(tonumber(x), tonumber(y), tonumber(z))
end

function utils.ManhattanDistance(v1, v2)
    return math.abs(v1.x - v2.x) + math.abs(v1.y - v2.y) + math.abs(v1.z - v2.z)
end

function utils.SerializeAndSave(content, filepath)
    local file = fs.open(filepath, "w")
    file.write(textutils.serialize(content))
    file.close()
end

function utils.ReadAndUnserialize(filepath)
    if fs.exists(filepath) then
        local file = fs.open(filepath, "r")
        local content = file.readAll()
        file.close()
        return textutils.unserialize(content)
    else
        return nil
    end
end

-- ...existing code...

utils.Heap = {}
utils.Heap.__index = utils.Heap

function utils.Heap:swap(i, j)
    self[i], self[j] = self[j], self[i]
end

function utils.Heap:push(node)
    table.insert(self, node)
    local i = #self
    while i > 1 do
        local j = math.floor(i / 2)
        if self[i].weight < self[j].weight then
            self:swap(i, j)
            i = j
        else
            break
        end
    end
end

function utils.Heap:siftDown(i)
    local size = #self
    while true do
        local left = 2 * i
        local right = left + 1
        local smallest = i

        if left <= size and self[left].weight < self[smallest].weight then
            smallest = left
        end
        if right <= size and self[right].weight < self[smallest].weight then
            smallest = right
        end
        if smallest == i then
            break
        end

        self:swap(i, smallest)
        i = smallest
    end
end

function utils.Heap:pop()
    if #self == 0 then
        return nil
    end

    local min = self[1]
    local last = table.remove(self)
    
    if #self > 0 then
        self[1] = last
        self:siftDown(1)
    end

    return min
end

return utils