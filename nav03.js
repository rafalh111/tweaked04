import {
    Vector, Heap, ManhattanDistance,
    duwsenDirectionVectors, FaceToIndex, 
    neswudDirectionVectors
} from './utils.js';

function flowCalculation(obstacle, neighbor) {
    const neighborDir = neighbor.direction;
    const flowDir = obstacle.direction;

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
            // fix modulo to handle negative results in JS
            const diff = ((obstacleFlowIndex - neighborFlowIndex) + 4) % 4;
            if (diff === 2) {
                return "AgainstFlow";
            }
        }
    }

    return "MergeFromSide";
}

export function aStar(bDirection, b, d, fuel, WorldMap, turtleObject) {
    const dKey = d.toString();

    if (!WorldMap) WorldMap = {};

    const queue = new Heap();
    queue.push({
        vector: b,
        weight: ManhattanDistance(b, d),
        stepCount: 0,
        turnCount: 0,
        direction: bDirection
    });

    const cameFrom = {};
    const visited = { [b.toString()]: true };

    while (queue.items.length > 0) {
        const current = queue.pop();
        const currentKey = current.vector.toString();

        // PATH RECONSTRUCTION
        if (currentKey === dKey) {
            const journeyPath = [];

            let node = current;
            while (node) {
                delete node.weight;
                delete node.stepCount;
                delete node.turnCount;

                if (turtleObject) {
                    node.turtles = node.turtles || [];
                    node.turtles.push(turtleObject.id);
                }

                journeyPath.unshift(node);
                const key = node.vector.toString();
                node = cameFrom[key];
            }

            journeyPath.shift();
            if (journeyPath.length > 0) {
                journeyPath[journeyPath.length - 1].special = { lastBlock: true };
            }

            return journeyPath;
        }

        // QUEUE BUILD
        if (current.stepCount * 2 < fuel) {
            const neighborVectors = [
                current.vector.add(new Vector(1, 0, 0)),
                current.vector.add(new Vector(-1, 0, 0)),
                current.vector.add(new Vector(0, 0, 1)),
                current.vector.add(new Vector(0, 0, -1)),
                current.vector.add(new Vector(0, 1, 0)),
                current.vector.add(new Vector(0, -1, 0))
            ];  

            for (const neighborVector of neighborVectors) {
                const neighborKey = neighborVector.toString();

                if (visited[neighborKey]) continue;
                if (WorldMap[neighborKey] && !WorldMap[neighborKey].direction) continue;

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
                    if (flow === "AgainstFlow") continue;
                    else if (flow === "PathFlow") flowResistance -= 1;
                    else flowResistance += 1;
                }

                // TURN
                let turnCount = neighbor.turnCount;
                if (current.direction !== neighbor.direction) {
                    turnCount += 1;
                }

                // WEIGHT
                const estimatedDistance = ManhattanDistance(neighborVector, d);
                neighbor.weight = estimatedDistance + neighbor.stepCount + turnCount + flowResistance;

                visited[neighborKey] = true;
                cameFrom[neighborKey] = current;
                queue.push(neighbor);
            }
        }
    }

    return false;
}