import {
    Vector, Heap, MultiManhattanDistance,
    duwsenDirectionVectors, FaceToIndex,
    getNeighbors, oppositeDirection
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

export function aStar(config, WorldMap, turtleObject) {
    if (!WorldMap) WorldMap = {};

    // --- QUEUE INIT ---
    const queue = new Heap();
    const start = {
        vector: config.beginning,
        direction: config.initialDirection,
        stepCount: 0,
        turnCount: 0,
        unixArriveTime: Date.now(),
        weight: MultiManhattanDistance(config.beginning, config.destinations),
        turtles: (WorldMap[config.beginning] && WorldMap[config.beginning].turtles) || {},
        syncDelay: 0
    };
    queue.push(start);

    const cameFrom = {};
    const bestCost = { [start.vector.toString()]: start.weight };

    let loopCount = 0;

    while (queue.items.length > 0) {
        loopCount++;
        const current = queue.pop();
        const currentKey = current.vector.toString();

        // --- PATH RECONSTRUCTION ---
        if (isDestination(config.destinations, currentKey)) {
            const journeyPath = [];
            let node = current;

            while (node) {
                const journeyStep = {
                    vector: node.vector,
                    direction: node.direction,
                    turtles: node.turtles || {}
                };

                if (turtleObject) {
                    journeyStep.turtles[turtleObject.id] = {
                        direction: node.direction,
                        unixArriveTime: node.unixArriveTime,
                        unixLeaveTime: journeyPath[0]?.turtles[turtleObject.id]?.unixArriveTime || null
                    };
                }

                journeyPath.unshift(journeyStep);
                node = cameFrom[node.vector.toString()];
            }

            journeyPath.shift(); // drop starting point
            return { journeyPath, totalSyncDelay: current.syncDelay || 0 };
        }

        // --- QUEUE BUILD ---
        if (current.stepCount * 2 < turtleObject.fuel) {
            const neighborVectors = getNeighbors(current.vector);

            for (const neighborVector of neighborVectors) {
                const neighborKey = neighborVector.toString();

                const directionKey = neighborVector.subtract(current.vector).toString();
                const neighbor = {
                    vector: neighborVector,
                    direction: duwsenDirectionVectors[directionKey],
                    stepCount: current.stepCount + 1,
                    turnCount: current.turnCount,
                    unixArriveTime: current.unixArriveTime + StepTime,
                    weight: current.weight + MultiManhattanDistance(neighborVector, config.destinations) + 1,
                    turtles: (WorldMap[neighborKey] && WorldMap[neighborKey].turtles) || {},
                    syncDelay: current.syncDelay
                };

                // --- BLOCKED ---
                if (WorldMap[neighborKey] && WorldMap[neighborKey].blocked) {
                    if (!config.dig) continue;
                    neighbor.weight += 100;
                    neighbor.unixArriveTime += DigTime;
                }

                // --- TURN COST ---
                if (!(neighbor.direction === "up" || neighbor.direction === "down") ||
                    current.direction === neighbor.direction) {
                    const currentDirIndex = FaceToIndex(current.direction);
                    const neighborDirIndex = FaceToIndex(neighbor.direction);
                    const diff = (neighborDirIndex - currentDirIndex + 4) % 4;

                    if (diff === 1 || diff === 3) {
                        neighbor.unixArriveTime += TurnTime;
                        neighbor.turnCount += 1;
                        neighbor.weight += 1;
                    } else if (diff === 2) {
                        neighbor.unixArriveTime += TurnTime * 2;
                        neighbor.turnCount += 2;
                        neighbor.weight += 2;
                    }
                }

                // --- FLOW ---
                for (const tid in neighbor.turtles) {
                    const turtle = neighbor.turtles[tid];

                    if (config.nonConformist) {
                        neighbor.weight += 2;
                    } else {
                        const flow = flowCalculation(turtle.direction, neighbor.direction);
                        if (flow === "PathFlow") {
                            neighbor.weight -= 1;
                        } else if (flow === "MergeFromSide") {
                            neighbor.weight += 1;
                        } else if (flow === "AgainstFlow") {
                            neighbor.weight += 2;
                        }
                    }

                    if (neighbor.unixArriveTime >= turtle.unixArriveTime) {
                        if (neighbor.unixArriveTime <= turtle.unixLeaveTime) {
                            const syncDelay = turtle.unixLeaveTime - neighbor.unixArriveTime + 200;
                            neighbor.weight += 10;
                            neighbor.syncDelay += syncDelay;
                            neighbor.unixArriveTime += syncDelay;
                        } else if (turtle.unixLeaveTime == null) {
                            neighbor.weight += 100;
                        }
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