import {
    Vector, Heap, MultiManhattanDistance,
    duwsenDirectionVectors, FaceToIndex, 
    getNeighbors
} from './utils.js';

function flowCalculation(obstacle, neighbor) {
    const neighborDir = neighbor.direction;
    const flowDir = obstacle.direction;

    // Perfect alignment with flow
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
            const diff = ((obstacleFlowIndex - neighborFlowIndex) + 4) % 4;
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

export function aStar(config, WorldMap = {}, turtleObject) {
    const queue = new Heap();
    queue.push({
        vector: config.beginning,
        weight: MultiManhattanDistance(config.beginning, config.destinations),
        stepCount: 0,
        turnCount: 0,
        direction: config.initialDirection
    });

    const cameFrom = {};
    const visited = { [config.beginning.toString()]: true };

    let loopCount = 0;

    while (queue.items.length > 0) {
        loopCount++;

        const current = queue.pop();
        const currentKey = current.vector.toString();

        // Periodic yield like Lua (optional in JS, here just a placeholder)
        if (loopCount % 1000 === 0) {
            // Simulated yield if running in async environment
            // await new Promise(r => setTimeout(r, 0));
        }

        // PATH RECONSTRUCTION
        if (isDestination(config.destinations, currentKey)) {
            const journeyPath = [];

            let node = current;
            while (node) {
                delete node.weight;

                if (turtleObject) {
                    node.turtles = node.turtles || [];
                    node.turtles.push(turtleObject.id);
                }

                journeyPath.unshift(node);
                node = cameFrom[node.vector.toString()];
            }

            journeyPath.shift();
            if (journeyPath.length > 0) {
                journeyPath[journeyPath.length - 1].special = { lastBlock: true };
            }

            return journeyPath;
        }

        // QUEUE BUILD
        if (current.stepCount * 2 < turtleObject.fuel) {
            const neighborVectors = getNeighbors(current.vector);

            for (const neighborVector of neighborVectors) {
                const neighborKey = neighborVector.toString();

                // Skip if already visited
                if (visited[neighborKey]) continue;
                // Skip if WorldMap entry exists without a direction
                if (WorldMap[neighborKey] && !WorldMap[neighborKey].direction) continue;

                // NEIGHBOR INIT
                const neighbor = {
                    vector: neighborVector,
                    turnCount: current.turnCount,
                    stepCount: current.stepCount + 1,
                    direction: duwsenDirectionVectors[
                        neighborVector.subtract(current.vector).toString()
                    ]
                };

                // FLOW
                let flowResistance = 0;
                if (WorldMap[neighborKey] && WorldMap[neighborKey].direction) {
                    const flow = flowCalculation(WorldMap[neighborKey], neighbor);
                    if (flow === "AgainstFlow") {
                        flowResistance += 2; // Penalize like Lua, not block
                    } else if (flow === "PathFlow") {
                        flowResistance -= 1;
                    } else {
                        flowResistance += 1;
                    }
                }

                // TURN
                let turnCount = neighbor.turnCount;
                if (current.direction !== neighbor.direction) {
                    turnCount += 1;
                }

                // WEIGHT
                const estimatedDistance = MultiManhattanDistance(neighborVector, config.destinations);
                neighbor.weight = estimatedDistance + neighbor.stepCount + turnCount + flowResistance;

                visited[neighborKey] = true;
                cameFrom[neighborKey] = current;
                queue.push(neighbor);
            }
        }
    }

    return false;
}
