import { prototype } from "ws";

// Direction arrays
export const neswDirections = ["north", "east", "south", "west"];
export const neswudDirections = ["north", "east", "south", "west", "up", "down"];

// FaceToIndex (Lua style)
export function FaceToIndex(face) {
    for (let i = 0; i < neswudDirections.length; i++) {
        if (neswudDirections[i] === face) {
            return i + 1; // match Lua's 1-based indexing
        }
    }
    return null;
}


export class Vector {
    constructor(x, y, z) {
        this.x = x;
        this.y = y;
        this.z = z;
    }
    
    add(v) {
        return new Vector(this.x + v.x, this.y + v.y, this.z + v.z);
    }

    subtract(v) {
        return new Vector(this.x - v.x, this.y - v.y, this.z - v.z);
    }
    
    toString() {
        return `${this.x},${this.y},${this.z}`; // matches Lua :tostring()
    }
    
    equals(v) {
        return this.x === v.x && this.y === v.y && this.z === v.z;
    }
}

// NESWUD direction vectors
export const neswudDirectionVectors = {
    north: new Vector(0, 0, -1),
    east:  new Vector(1, 0, 0),
    south: new Vector(0, 0, 1),
    west:  new Vector(-1, 0, 0),
    up:    new Vector(0, 1, 0),
    down:  new Vector(0, -1, 0)
};

// Reverse lookup: vector → direction
export const duwsenDirectionVectors = {
    [new Vector(0, 0, -1).toString()]: "north",
    [new Vector(1, 0, 0).toString()]:  "east",
    [new Vector(0, 0, 1).toString()]:  "south",
    [new Vector(-1, 0, 0).toString()]: "west",
    [new Vector(0, 1, 0).toString()]:  "up",
    [new Vector(0, -1, 0).toString()]: "down"
};

export function ManhattanDistance(v1, v2) {
    return Math.abs(v1.x - v2.x) +
           Math.abs(v1.y - v2.y) +
           Math.abs(v1.z - v2.z);
}

export function MultiManhattanDistance(v1, v2Array) {
    let lowestDistance = null;
    for (const v2 of v2Array) {
        const distance = ManhattanDistance(v1, v2);
        if (lowestDistance === null || distance < lowestDistance) {
            lowestDistance = distance;
        }
    }
    return lowestDistance;
}

export class Heap {
    constructor() {
        this.items = [];
    }

    swap(i, j) {
        [this.items[i], this.items[j]] = [this.items[j], this.items[i]];
    }

    push(node) {
        this.items.push(node);
        let i = this.items.length - 1;
        
        while (i > 0) {
            let j = Math.floor((i - 1) / 2);
            if (this.items[i].weight < this.items[j].weight) {
                this.swap(i, j);
                i = j;
            } else {
                break;
            }
        }
    }

    siftDown(i) {
        let size = this.items.length;

        while (true) {
            let left = 2 * i + 1;
            let right = left + 1;
            let smallest = i;

            if (left < size && this.items[left].weight < this.items[smallest].weight) {
                smallest = left;
            }
            if (right < size && this.items[right].weight < this.items[smallest].weight) {
                smallest = right;
            }
            if (smallest === i) break;

            this.swap(i, smallest);
            i = smallest;
        }
    }

    pop() {
        if (this.items.length === 0) return null;

        let min = this.items[0];
        let last = this.items.pop();

        if (this.items.length > 0) {
            this.items[0] = last;
            this.siftDown(0);
        }

        return min;
    }

    size() {
        return this.items.length;
    }
}
