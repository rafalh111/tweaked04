import {
    Vector, Heap, MultiManhattanDistance,
    duwsenDirectionVectors, neswudToFrblud,
    FaceToIndex, getNeighbors, oppositeDirection
} from './utils.js';

const StepTime = 400;
const TurnTime = 400;
const DigTime = 500;
const SafetyMargin = 1000;

function flowCalculation(flowDir, neighborDir) {
    if (neighborDir === flowDir) return "PathFlow";

    if (
        neighborDir === "up" || neighborDir === "down" ||
        flowDir === "up" || flowDir === "down"
    ) {
        if (
            (neighborDir === "up" && flowDir === "down") ||
            (neighborDir === "down" && flowDir === "up")
        ) {
            return "AgainstFlow";
        }
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

export async function aStar(args, WorldMap = {}, turtleObject) {
    const queue = new Heap();

    const start = {
        vector: args["beginning"],
        neswudDirection: args["initialDirection"],
        fuelCost: 0,
        unixArriveTime: Date.now(),
        weight: MultiManhattanDistance(args["beginning"], args["destinations"]),
        turtles: {},
        waitTime: 0,
        turtleFace: args["initialDirection"],
        frbludDirection: null
    };

    queue.push(start);

    const cameFrom = {};
    const bestCost = { [start.vector.toString()]: start.weight };
    let loopCount = 0;

    while (queue.size() > 0) {
        loopCount++;
        const current = queue.pop();
        const currentKey = current.vector.toString();

        const InitialWeight = MultiManhattanDistance(current.vector, args["destinations"]);

        // occasional yield (like os.queueEvent/pullEvent in Lua)
        if (loopCount % 1000 === 0) {
            await new Promise(resolve => setTimeout(resolve, 0));

            if (
                loopCount % 100000 === 0 &&
                !args["reverseCheck"] &&
                current["weight"] > InitialWeight * 2 &&
                !args["dig"]
            ) {
                if (args["isReverse"]) return false;

                let reachable = false;
                for (const destination of args["destinations"]) {
                    const reverseArgs = {
                        beginning: destination,
                        destinations: [args["beginning"]],
                        initialDirection: oppositeDirection(current["direction"]),
                        isReverse: true,
                        reverseCheck: true
                    };

                    if (await aStar(reverseArgs, WorldMap, turtleObject)) {
                        reachable = true;
                        break;
                    }
                }

                if (!reachable) return false;
                args["reverseCheck"] = true;
            }
        }

        // --- PATH RECONSTRUCTION ---
        if (isDestination(args["destinations"], currentKey)) {
            const journeyPath = [];
            let node = current;

            while (node) {
                const journeyStep = {
                    vector: node.vector,
                    frbludDirection: node.frbludDirection,
                    turtles: node.turtles || {},
                    waitTime: node.waitTime
                };

                if (turtleObject) {
                    journeyStep.turtles[turtleObject.id] = {
                        direction: node.neswudDirection,
                        unixArriveTime: node.unixArriveTime,
                        unixLeaveTime: journeyPath[0]?.turtles?.[turtleObject.id]?.unixArriveTime || null
                    };
                }

                journeyPath.unshift(journeyStep);
                node = cameFrom[node.vector.toString()];
            }

            journeyPath.shift(); // drop starting point
            return journeyPath;
        }

        // --- QUEUE BUILD ---
        if (current.fuelCost * 2 < turtleObject.fuel) {
            const neighborVectors = getNeighbors(current.vector);

            for (const neighborVector of neighborVectors) {
                const neighborKey = neighborVector.toString();
                const directionKey = neighborVector.subtract(current.vector).toString();

                const neighbor = {
                    vector: neighborVector,
                    neswudDirection: duwsenDirectionVectors[directionKey],
                    fuelCost: current.fuelCost + 1,
                    unixArriveTime: current.unixArriveTime + StepTime,
                    weight: current.weight + MultiManhattanDistance(neighborVector, args["destinations"]) + 1,
                    turtles: WorldMap[neighborKey]?.turtles || {},
                    waitTime: 0,
                    turtleFace: (["up", "down"].includes(duwsenDirectionVectors[directionKey]))
                        ? current.turtleFace
                        : duwsenDirectionVectors[directionKey],
                    frbludDirection: neswudToFrblud(current.turtleFace, duwsenDirectionVectors[directionKey])
                };

                // BLOCKED NEIGHBOR
                if (WorldMap[neighborKey]?.blocked) {
                    if (!args["dig"]) continue;
                    neighbor.weight += 100;
                    neighbor.unixArriveTime += DigTime;
                }

                // TURN COST
                if (neighbor.frbludDirection === "right" || neighbor.frbludDirection === "left") {
                    neighbor.weight += 1;
                    neighbor.unixArriveTime += TurnTime;
                } else if (neighbor.frbludDirection === "back") {
                    neighbor.weight += 2;
                    neighbor.unixArriveTime += TurnTime * 2;
                }

                // OTHER TURTLES
                for (const tid in neighbor.turtles) {
                    const turtle = neighbor.turtles[tid];

                    // arrive check
                    if (turtle.unixArriveTime && neighbor.unixArriveTime - SafetyMargin >= turtle.unixArriveTime) {
                        if (!turtle.unixLeaveTime) continue;

                        // leave check
                        if (neighbor.unixArriveTime + SafetyMargin <= turtle.unixLeaveTime) {
                            const waitTime = turtle.unixLeaveTime - neighbor.unixArriveTime;
                            neighbor.unixArriveTime += waitTime;
                            neighbor.waitTime = (neighbor.waitTime || 0) + waitTime;
                            neighbor.weight += Math.ceil(waitTime / 1000);
                        }
                    }

                    if (args["nonConformist"]) {
                        neighbor.weight += 1;
                    } else {
                        neighbor.weight -= 1;
                    }
                }

                for (const tid in current.turtles) {
                    const turtle = current.turtles[tid];
                    if (turtle.unixArriveTime + SafetyMargin < neighbor.unixArriveTime) {
                        continue; // can't move into space occupied
                    }
                }

                if (neighbor.weight >= (bestCost[neighborKey] ?? Infinity)) continue;

                bestCost[neighborKey] = neighbor.weight;
                cameFrom[neighborKey] = current;
                queue.push(neighbor);
            }
        }
    }

    return false;
}
