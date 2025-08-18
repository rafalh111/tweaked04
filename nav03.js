import {
    Vector, Heap, MultiManhattanDistance,
    duwsenDirectionVectors, FaceToIndex,
    getNeighbors, oppositeDirection
} from './utils.js';

function flowCalculation(flowDir, neighborDir) {
    if (neighborDir === flowDir) {
        return "PathFlow";
    }

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
            if (diff === 2) {
                return "AgainstFlow";
            }
        }
    }

    return "MergeFromSide";
}

function isDestination(destinations, currentKey) {
    for (const destination of destinations) {
        if (destination.toString() === currentKey) {
            return true;
        }
    }
    return false;
}

function unixTimeCalculation(stepCount, turnCount, digCount) {
    return Date.now() + stepCount * 400 + turnCount * 200 + digCount * 500;
}

export function aStar(config, WorldMap = {}, turtleObject) {
    // --- QUEUE INIT ---
    const queue = new Heap();
    queue.push({
        vector: config.beginning,
        weight: MultiManhattanDistance(config.beginning, config.destinations),
        stepCount: 0,
        turnCount: 0,
        digCount: 0,
        direction: config.initialDirection,
        turtles: {}
    });

    const cameFrom = {};
    const bestCost = { [config.beginning.toString()]: queue.items[0].weight };

    let loopCount = 0;

    while (queue.items.length > 0) {
        loopCount++;

        const current = queue.pop();
        const currentKey = current.vector.toString();

        const InitialWeight = MultiManhattanDistance(current.vector, config.destinations);

        // Periodic checks
        if (loopCount % 100000 === 0) {
            if (!config.reverseCheck && current.weight > InitialWeight * 2 && !config.dig) {
                if (config.isReverse) return false;

                let reachable = false;
                for (const destination of config.destinations) {
                    const reverseConfig = {
                        beginning: destination,
                        destinations: [config.beginning],
                        initialDirection: oppositeDirection(current.direction),
                        isReverse: true,
                        reverseCheck: true
                    };

                    if (aStar(reverseConfig, WorldMap, turtleObject)) {
                        reachable = true;
                        break;
                    }
                }

                if (!reachable) {
                    console.log("The destinations is unreachable.");
                    return false;
                }

                config.reverseCheck = true;
            }
        }

        // PATH RECONSTRUCTION
        if (isDestination(config.destinations, currentKey)) {
            const journeyPath = [];
            const totalTimeToWait = current.timeToWait || 0;

            let node = current;
            while (node) {
                const journeyStep = {
                    vector: node.vector,
                    turtles: node.turtles || {}
                };

                if (turtleObject) {
                    journeyStep.turtles[turtleObject.id] = {
                        direction: node.direction,
                        unixTime: unixTimeCalculation(node.stepCount, node.turnCount, node.digCount),
                    };
                }

                journeyPath.unshift(journeyStep);
                node = cameFrom[node.vector.toString()];
            }

            journeyPath.shift(); // remove starting point
            return { journeyPath, totalTimeToWait };
        }

        // QUEUE BUILD
        if (current.stepCount * 2 < turtleObject.fuel) {
            const neighborVectors = getNeighbors(current.vector);

            for (const neighborVector of neighborVectors) {
                const neighborKey = neighborVector.toString();

                // Init
                const directionKey = neighborVector.subtract(current.vector).toString();
                const neighbor = {
                    turtles: (WorldMap[neighborKey] && WorldMap[neighborKey].turtles) || {},
                    direction: duwsenDirectionVectors[directionKey],
                    stepCount: current.stepCount + 1,
                    turnCount: current.turnCount || 0,
                    digCount: current.digCount || 0,
                    vector: neighborVector,
                    flowResistance: 0,
                    timeToWait: 0,
                    weight: 0,
                };

                // Blocked check
                if (WorldMap[neighborKey] && WorldMap[neighborKey].blocked) {
                    if (!config.dig) continue;
                    neighbor.digCount = current.digCount + 1;
                }

                // FLOW
                for (const tid in neighbor.turtles) {
                    const turtle = neighbor.turtles[tid];
                    const timeDiff = Math.abs(
                        unixTimeCalculation(turtle.stepCount, turtle.turnCount, turtle.digCount) - turtle.unixTime
                    );

                    if (timeDiff < 5000) {
                        neighbor.flowResistance += 10;
                        neighbor.timeToWait = Math.max(neighbor.timeToWait, timeDiff);
                    }

                    const flow = flowCalculation(turtle.direction, neighbor.direction);
                    if (flow === "AgainstFlow") {
                        neighbor.flowResistance += 2;
                    } else if (flow === "PathFlow") {
                        neighbor.flowResistance -= 1;
                    } else {
                        neighbor.flowResistance += 1;
                    }
                }

                // TURN
                if (!(neighbor.direction === "up" || neighbor.direction === "down") ||
                    current.direction === neighbor.direction) {
                    const currentDirIndex = FaceToIndex(current.direction);
                    const neighborDirIndex = FaceToIndex(neighbor.direction);

                    const diff = (neighborDirIndex - currentDirIndex + 4) % 4;
                    if (diff === 1 || diff === 3) {
                        neighbor.turnCount += 1;
                    } else if (diff === 2) {
                        neighbor.turnCount += 2;
                    }
                }

                // WEIGHT
                const estimatedDistance = MultiManhattanDistance(neighborVector, config.destinations);
                neighbor.weight = estimatedDistance +
                                  neighbor.stepCount +
                                  neighbor.turnCount +
                                  neighbor.flowResistance;

                if (neighbor.weight >= (bestCost[neighborKey] ?? Infinity)) continue;

                bestCost[neighborKey] = neighbor.weight;
                cameFrom[neighborKey] = current;
                queue.push(neighbor);
            }
        }
    }

    return false;
}
