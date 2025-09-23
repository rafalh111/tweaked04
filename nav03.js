import {
    Vector, Heap, MultiManhattanDistance,
    duwsenDirectionVectors, neswudToFrblud,
    FaceToIndex, getNeighbors, oppositeDirection, TableContains
} from './utils.js';

const StepTime = 400;
const TurnTime = 400;
const DigTime = 500;

function flowCalculation(flowDir, neighborDir) {
    if (neighborDir === flowDir) return "PathFlow";

    if (
        neighborDir === "up" || neighborDir === "down" ||
        flowDir === "up" || flowDir === "down"
    ) {
        if (
            (neighborDir === "up" && flowDir === "down") ||
            (neighborDir === "down" && flowDir === "up")
        ) return "AgainstFlow";
    } else {
        const obstacleFlowIndex = FaceToIndex(flowDir);
        const neighborFlowIndex = FaceToIndex(neighborDir);
        if (obstacleFlowIndex !== null && neighborFlowIndex !== null) {
            const diff = (obstacleFlowIndex - neighborFlowIndex + 4) % 4;
            if (diff === 2) return "AgainstFlow";
        }
    }

    return "MergeFromSide";
}

function isDestination(destinations, currentKey) {
    return destinations.some(dest => dest.toString() === currentKey);
}

export async function aStar(config, WorldMap = {}, turtleObject) {
    const queue = new Heap();
    const start = {
        vector: config["beginning"],
        neswudDirection: config["initialDirection"],
        fuelCost: 0,
        unixArriveTime: Date.now(),
        weight: MultiManhattanDistance(config["beginning"], config["destinations"]),
        turtles: (WorldMap[config["beginning"]]?.turtles) || {},
        syncDelay: 0,
        turtleFace: config["initialDirection"],
        frbludDirection: null
    };
    queue.push(start);

    const cameFrom = {};
    const bestCost = { [start["vector"].toString()]: start["weight"] };
    let loopCount = 0;

    while (queue.items["length"] > 0) {
        loopCount++;
        const current = queue.pop();
        const currentKey = current["vector"].toString();

        const initialWeight = MultiManhattanDistance(current["vector"], config["destinations"]);

        // --- REVERSE PATH CHECK ---
        if (
            loopCount % 100000 === 0 &&
            !config["reverseCheck"] &&
            current["weight"] > initialWeight * 2 &&
            !config["dig"]
        ) {
            if (config["isReverse"]) return false;

            let reachable = false;
            for (const destination of config["destinations"]) {
                const reverseConfig = {
                    beginning: destination,
                    destinations: [config["beginning"]],
                    initialDirection: oppositeDirection(current["neswudDirection"]),
                    isReverse: true,
                    reverseCheck: true
                };
                if (await aStar(reverseConfig, WorldMap, turtleObject)) {
                    reachable = true;
                    break;
                }
            }

            if (!reachable) return false;
            config["reverseCheck"] = true;
        }

        // --- PATH RECONSTRUCTION ---
        if (isDestination(config["destinations"], currentKey)) {
            const journeyPath = [];
            let node = current;

            while (node) {
                const journeyStep = {
                    vector: node["vector"],
                    frbludDirection: node["frbludDirection"],
                    turtles: node["turtles"] || {},
                    syncDelay: node["syncDelay"]
                };

                if (turtleObject) {
                    journeyStep.turtles[turtleObject.id] = {
                        direction: node["neswudDirection"],
                        unixArriveTime: node["unixArriveTime"],
                        unixLeaveTime: journeyPath[0]?.turtles?.[turtleObject.id]?.unixArriveTime || null
                    };
                }

                journeyPath.unshift(journeyStep);
                node = cameFrom[node["vector"].toString()];
            }

            if (turtleObject && config["doAtTheEnd"] && !TableContains(config["doAtTheEnd"], "go")) {
                journeyPath[journeyPath["length"] - 2]?.turtles?.[turtleObject.id] &&
                    (journeyPath[journeyPath["length"] - 2].turtles[turtleObject.id]["unixLeaveTime"] = null);
            }

            journeyPath.shift(); // drop starting point
            return { journeyPath, totalSyncDelay: current["syncDelay"] || 0 };
        }

        // --- QUEUE BUILD ---
        if (current["fuelCost"] * 2 < turtleObject.fuel) {
            const neighborVectors = getNeighbors(current["vector"]);

            for (const neighborVector of neighborVectors) {
                const neighborKey = neighborVector.toString();
                const directionKey = neighborVector.subtract(current["vector"]).toString();

                const neighbor = {
                    vector: neighborVector,
                    neswudDirection: duwsenDirectionVectors[directionKey] ?? current["neswudDirection"],
                    fuelCost: current["fuelCost"] + 1,
                    unixArriveTime: current["unixArriveTime"] + StepTime,
                    weight: current["weight"] + MultiManhattanDistance(neighborVector, config["destinations"]) + 1,
                    turtles: WorldMap[neighborKey]?.turtles || {},
                    syncDelay: 0,
                    turtleFace: (["up", "down"].includes(duwsenDirectionVectors[directionKey])) ? current["turtleFace"] : duwsenDirectionVectors[directionKey],
                    frbludDirection: neswudToFrblud(current["turtleFace"], duwsenDirectionVectors[directionKey])
                };

                // BLOCKED
                if (WorldMap[neighborKey]?.blocked) {
                    if (!config["dig"]) continue;
                    neighbor["weight"] += 100;
                    neighbor["unixArriveTime"] += DigTime;
                }

                // TURN COST
                if (["right", "left"].includes(neighbor["frbludDirection"])) {
                    neighbor["weight"] += 1;
                    neighbor["unixArriveTime"] += TurnTime;
                } else if (neighbor["frbludDirection"] === "back") {
                    neighbor["weight"] += 2;
                    neighbor["unixArriveTime"] += TurnTime * 2;
                }

                // FLOW & SYNC
                for (const tid in neighbor["turtles"]) {
                    const turtle = neighbor["turtles"][tid];
                    if (config["nonConformist"]) {
                        neighbor["weight"] += 2;
                    } else {
                        const flow = flowCalculation(turtle["direction"], neighbor["neswudDirection"]);
                        if (flow === "PathFlow") neighbor["weight"] -= 1;
                        else if (flow === "MergeFromSide") neighbor["weight"] += 1;
                        else if (flow === "AgainstFlow") neighbor["weight"] += 2;
                    }

                    if (neighbor["unixArriveTime"] >= turtle["unixArriveTime"]) {
                        if (turtle["unixLeaveTime"] && neighbor["unixArriveTime"] <= turtle["unixLeaveTime"]) {
                            const syncDelay = turtle["unixLeaveTime"] - neighbor["unixArriveTime"];
                            neighbor["unixArriveTime"] += syncDelay;
                            neighbor["syncDelay"] += syncDelay;
                            neighbor["weight"] += Math.ceil(syncDelay / 1000);
                        } else if (!turtle["unixLeaveTime"]) continue;
                    }
                }

                if (neighbor["weight"] >= (bestCost[neighborKey] ?? Infinity)) continue;

                bestCost[neighborKey] = neighbor["weight"];
                cameFrom[neighborKey] = current;
                queue.push(neighbor);
            }
        }

        // Optional async yield for long-running searches
        if (loopCount % 1000 === 0) await new Promise(resolve => setTimeout(resolve, 0));
    }

    return false;
}
