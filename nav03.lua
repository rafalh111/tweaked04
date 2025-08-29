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

function nav.aStar(args, WorldMap, turtleObject)
    if not WorldMap then
        WorldMap = {}
    end

    ---/*%$# QUEUE INIT #$%*\---
    local queue = {}
    
    queue[1] = {
        vector = args["beginning"],
        neswudDirection = args["initialDirection"],
        fuelCost = 0,
        unixArriveTime = os.epoch("utc"),
        weight = utils.MultiManhattanDistance(args["beginning"], args["destinations"]),
        turtles = WorldMap[args["beginning"]]["turtles"] or {},
        syncDelay = 0,
        turtleFace = args["initialDirection"],
        frbludDirection = nil
    }

    setmetatable(queue, utils.Heap)

    local cameFrom = {}  -- key: position string, value: parent neighbor
    local bestCost = {[queue[1]["vector"]:tostring()] = queue[1]["weight"]}

    local loopCount = 0

    while #queue > 0 do
        loopCount = loopCount + 1

        local current = queue:pop()
        local currentKey = current["vector"]:tostring()

        local InitialWeight = utils.MultiManhattanDistance(current["vector"], args["destinations"])
        if loopCount % 1000 == 0 then
            print("A* loop count: " .. loopCount)

            if loopCount % 100000 == 0 then
                if not args["reverseCheck"] and current["weight"] > InitialWeight * 2 and
                   not args["dig"] then
                    print("Current path is too long, checking for reverse path...")
                    if args["isReverse"] then
                        return false
                    end
                    
                    local reachable = false
                    for _, destination in ipairs(args["destinations"]) do
                        local reverseargs = {
                            beginning = destination,
                            destinations = args["beginning"],
                            initialDirection = utils.oppositeDirection(current["direction"]),
                            isReverse = true,
                            reverseCheck = true
                        }

                        if nav.aStar(reverseargs, WorldMap, turtleObject) then
                            reachable = true
                            break
                        end
                    end

                    if not reachable then
                        print("The destinations is unreachable.")
                        return false
                    end
                    
                    args["reverseCheck"] = true
                end
            end

            os.queueEvent("yield")
            os.pullEvent()
        end
        
        ---/*%$# PATH RECONSTRUCTION #$%*\---
        if isDestination(args["destinations"], currentKey) then
            local journeyPath = {}

            while current do
                local journeyStep = {}
                journeyStep["vector"] = current["vector"]
                journeyStep["frbludDirection"] = current["frbludDirection"]
                journeyStep["turtles"] = current["turtles"] or {}
                journeyStep["syncDelay"] = current["syncDelay"]

                if turtleObject then
                    journeyStep["turtles"][turtleObject["id"]] = {
                        direction = current["neswudDirection"],
                        unixArriveTime = current["unixArriveTime"],
                        unixLeaveTime = journeyPath[1]["turtles"][turtleObject["id"]]["unixArriveTime"] or nil
                    }
                end
                
                table.insert(journeyPath, 1, journeyStep)
                current = cameFrom[current["vector"]:tostring()]
            end

            if turtleObject and args.doAtTheEnd and not utils.TableContains(args.doAtTheEnd, "go") then
                journeyPath[#journeyPath - 1]["turtles"][turtleObject["id"]]["unixLeaveTime"] = nil
            end

            table.remove(journeyPath, 1)
            return journeyPath
        end

        ---/*%$# QUEUE BUILD #$%*\---
        if current["fuelCost"] * 2 < turtleObject["fuel"] then
            local neighborVectors = utils.getNeighbors(current["vector"])
            
            for _, neighborVector in ipairs(neighborVectors) do
                local neighborKey = neighborVector:tostring()

                -- NEIGHBOR INIT
                local neighbor = {}
                neighbor["vector"] = neighborVector
                neighbor["neswudDirection"] = utils["duwsenDirectionVectors"][neighborVector:sub(current.vector):tostring()]
                neighbor["fuelCost"] = current["fuelCost"] + 1
                neighbor["unixArriveTime"] = current["unixArriveTime"] + StepTime
                neighbor["weight"] = current["weight"] + utils.MultiManhattanDistance(neighborVector, args["destinations"]) + 1
                neighbor["turtles"] = WorldMap[neighborKey] and WorldMap[neighborKey].turtles or {}
                neighbor["syncDelay"] = 0
                if utils.neswudDirections[neighbor["neswudDirection"]] > 4 then
                    neighbor["turtleFace"] = current["turtleFace"]
                else
                    neighbor["turtleFace"] = neighbor["neswudDirection"]
                end
                neighbor["frbludDirection"] = utils.neswudToFrblud(current["turtleFace"], neighbor["neswudDirection"])
                
                -- BLOCKED NEIGHBOR CHECK
                if WorldMap[neighborKey] and WorldMap[neighborKey]["blocked"] then           
                    if not args["dig"] then
                        goto continue  -- Skip blocked neighbors unless digging is allowed
                    end

                    neighbor["weight"] = neighbor["weight"] + 100
                    neighbor["unixArriveTime"] = neighbor["unixArriveTime"] + DigTime
                end

                -- TURN
                if neighbor["frbludDirection"] == "right" or neighbor["frbludDirection"] == "left" then
                    neighbor["weight"] = neighbor["weight"] + 1
                    neighbor["unixArriveTime"] = neighbor["unixArriveTime"] + TurnTime
                elseif neighbor["frbludDirection"] == "back" then
                    neighbor["weight"] = neighbor["weight"] + 2
                    neighbor["unixArriveTime"] = neighbor["unixArriveTime"] + TurnTime * 2
                end

                -- FLOW
                for _, turtle in pairs(neighbor["turtles"]) do
                    if args["nonConformist"] then
                        neighbor["weight"] = neighbor["weight"] + 2
                    else
                        local flow = flowCalculation(turtle["direction"], neighbor["neswudDirection"])
                        if flow == "PathFlow" then
                            neighbor["weight"] = neighbor["weight"] - 1
                        elseif flow == "MergeFromSide" then
                            neighbor["weight"] = neighbor["weight"] + 1
                        elseif flow == "AgainstFlow" then
                            neighbor["weight"] = neighbor["weight"] + 2
                        end
                    end
                end

                -- COLLISION
                for _, turtle in pairs(neighbor["turtles"]) do
                    if neighbor["unixArriveTime"] >= turtle["unixArriveTime"] then 
                        if turtle["unixLeaveTime"] and neighbor["unixArriveTime"] <= turtle["unixLeaveTime"] then
                            local syncDelay = turtle["unixLeaveTime"] - neighbor["unixArriveTime"]
                            neighbor["unixArriveTime"] = neighbor["unixArriveTime"] + syncDelay
                            neighbor["syncDelay"] = (neighbor["syncDelay"] or 0) + syncDelay
                            neighbor["weight"] = neighbor["weight"] + math.ceil(syncDelay / 1000)  -- 1 weight per second of waiting
                        elseif not turtle["unixLeaveTime"] then
                            goto continue
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