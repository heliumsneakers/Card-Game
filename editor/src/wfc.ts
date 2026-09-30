import type { Direction, RoomTemplate, TileMetadata } from "./tileCatalog";

export interface GeneratedCell {
  x: number;
  y: number;
  tileId: string;
  objectId?: string;
  enemySpawn?: boolean;
}

export interface GeneratedRoom {
  width: number;
  height: number;
  biome: string;
  seed: number;
  attempt: number;
  cells: GeneratedCell[];
}

export type WfcResult =
  | { ok: true; room: GeneratedRoom }
  | { ok: false; error: string; attempts: number };

const directions: Direction[] = ["west", "south", "east", "north"];
const offsets: Record<Direction, readonly [number, number]> = {
  west: [-1, 0], south: [0, 1], east: [1, 0], north: [0, -1],
};
const opposite: Record<Direction, Direction> = {
  west: "east", south: "north", east: "west", north: "south",
};

// Park-Miller RNG: deterministic in browsers, tests, and the eventual Lua port.
export function seededRandom(seed: number): () => number {
  let state = Math.floor(Math.abs(seed || 1)) % 2147483647;
  if (state === 0) state = 1;
  return () => {
    state = (state * 48271) % 2147483647;
    return state / 2147483647;
  };
}

function integer(random: () => number, minimum: number, maximum: number): number {
  return minimum + Math.floor(random() * (maximum - minimum + 1));
}

function compatible(a: TileMetadata, direction: Direction, b: TileMetadata): boolean {
  const left = a.sockets[direction];
  const right = b.sockets[opposite[direction]];
  return left === "*" || right === "*" || left === right;
}

function entropy(possibilities: Set<number>, tiles: TileMetadata[]): number {
  let sum = 0;
  let sumWeightLogWeight = 0;
  for (const index of possibilities) {
    const weight = Math.max(tiles[index].weight, 0.000001);
    sum += weight;
    sumWeightLogWeight += weight * Math.log(weight);
  }
  return Math.log(sum) - sumWeightLogWeight / sum;
}

function weightedObservation(possibilities: Set<number>, tiles: TileMetadata[], random: () => number): number {
  let total = 0;
  for (const index of possibilities) total += Math.max(tiles[index].weight, 0.000001);
  let roll = random() * total;
  for (const index of possibilities) {
    roll -= Math.max(tiles[index].weight, 0.000001);
    if (roll <= 0) return index;
  }
  return [...possibilities][possibilities.size - 1];
}

function weightedTile(tiles: TileMetadata[], random: () => number): TileMetadata {
  return tiles[weightedObservation(new Set(tiles.map((_, index) => index)), tiles, random)];
}

function solve(
  width: number,
  height: number,
  tiles: TileMetadata[],
  pins: RoomTemplate["pins"],
  random: () => number,
): number[] | undefined {
  const all = tiles.map((_, index) => index);
  const wave = Array.from({ length: width * height }, () => new Set(all));
  const queue: number[] = [];

  for (const pin of pins) {
    if (pin.x < 0 || pin.y < 0 || pin.x >= width || pin.y >= height) continue;
    const tileIndex = tiles.findIndex((tile) => tile.id === pin.tileId);
    if (tileIndex < 0) return undefined;
    const cellIndex = pin.x + pin.y * width;
    wave[cellIndex] = new Set([tileIndex]);
    queue.push(cellIndex);
  }

  const propagate = (): boolean => {
    while (queue.length > 0) {
      const sourceIndex = queue.pop()!;
      const sourceX = sourceIndex % width;
      const sourceY = Math.floor(sourceIndex / width);
      for (const direction of directions) {
        const [dx, dy] = offsets[direction];
        const x = sourceX + dx;
        const y = sourceY + dy;
        if (x < 0 || y < 0 || x >= width || y >= height) continue;
        const neighborIndex = x + y * width;
        const neighbor = wave[neighborIndex];
        let changed = false;
        for (const candidate of [...neighbor]) {
          let supported = false;
          for (const source of wave[sourceIndex]) {
            if (compatible(tiles[source], direction, tiles[candidate])) { supported = true; break; }
          }
          if (!supported) { neighbor.delete(candidate); changed = true; }
        }
        if (neighbor.size === 0) return false;
        if (changed) queue.push(neighborIndex);
      }
    }
    return true;
  };

  if (!propagate()) return undefined;

  while (true) {
    let lowest = Number.POSITIVE_INFINITY;
    let selected = -1;
    for (let index = 0; index < wave.length; index += 1) {
      if (wave[index].size <= 1) continue;
      // Same entropy heuristic and tiny random tie-breaker used by the original model.
      const score = entropy(wave[index], tiles) + random() * 1e-6;
      if (score < lowest) { lowest = score; selected = index; }
    }
    if (selected < 0) break;
    const observed = weightedObservation(wave[selected], tiles, random);
    wave[selected] = new Set([observed]);
    queue.push(selected);
    if (!propagate()) return undefined;
  }

  return wave.map((possibilities) => possibilities.values().next().value as number);
}

function placeObjectsAndSpawns(
  cells: GeneratedCell[],
  width: number,
  height: number,
  terrain: TileMetadata[],
  objects: TileMetadata[],
  template: RoomTemplate,
  random: () => number,
): void {
  const terrainById = new Map(terrain.map((tile) => [tile.id, tile]));
  const free = cells.filter((cell) => terrainById.get(cell.tileId)?.walkable);
  for (const cell of free) {
    if (objects.length === 0 || random() >= template.objectDensity) continue;
    const object = weightedTile(objects, random);
    cell.objectId = object.id;
  }

  const spawnCandidates = free.filter((cell) => !cell.objectId);
  const desired = Math.min(spawnCandidates.length, integer(random, template.minimumEnemySpawns, template.maximumEnemySpawns));
  for (let count = 0; count < desired; count += 1) {
    const index = Math.floor(random() * spawnCandidates.length);
    const [cell] = spawnCandidates.splice(index, 1);
    cell.enemySpawn = true;
  }
}

export function generateRoom(catalog: TileMetadata[], template: RoomTemplate, seed: number): WfcResult {
  if (!Number.isInteger(template.minWidth) || !Number.isInteger(template.maxWidth) || template.minWidth < 1 || template.maxWidth < template.minWidth) {
    return { ok: false, error: "Width bounds must be positive whole numbers, with maximum width at least minimum width.", attempts: 0 };
  }
  if (!Number.isInteger(template.minHeight) || !Number.isInteger(template.maxHeight) || template.minHeight < 1 || template.maxHeight < template.minHeight) {
    return { ok: false, error: "Height bounds must be positive whole numbers, with maximum height at least minimum height.", attempts: 0 };
  }
  if (!Number.isInteger(template.minimumEnemySpawns) || !Number.isInteger(template.maximumEnemySpawns) || template.minimumEnemySpawns < 0 || template.maximumEnemySpawns < template.minimumEnemySpawns) {
    return { ok: false, error: "Enemy spawn bounds must be non-negative whole numbers, with maximum at least minimum.", attempts: 0 };
  }
  if (!Number.isInteger(template.maxAttempts) || template.maxAttempts < 1) {
    return { ok: false, error: "The WFC retry limit must be a positive whole number.", attempts: 0 };
  }
  if (!Number.isFinite(template.objectDensity) || template.objectDensity < 0 || template.objectDensity > 1) {
    return { ok: false, error: "Object density must be between 0% and 100%.", attempts: 0 };
  }
  const terrain = catalog.filter((tile) => tile.enabled && tile.layer === "terrain" && tile.biomes.includes(template.biome) && tile.weight > 0);
  const objects = catalog.filter((tile) => tile.enabled && tile.layer === "object" && tile.biomes.includes(template.biome) && tile.weight > 0);
  if (terrain.length === 0) return { ok: false, error: `No enabled terrain tiles belong to the ${template.biome} biome.`, attempts: 0 };

  for (let attempt = 0; attempt < template.maxAttempts; attempt += 1) {
    const random = seededRandom(seed + attempt * 104729);
    const width = integer(random, template.minWidth, template.maxWidth);
    const height = integer(random, template.minHeight, template.maxHeight);
    const observed = solve(width, height, terrain, template.pins, random);
    if (!observed) continue;
    const cells = observed.map((tileIndex, index) => ({
      x: index % width,
      y: Math.floor(index / width),
      tileId: terrain[tileIndex].id,
    }));
    placeObjectsAndSpawns(cells, width, height, terrain, objects, template, random);
    return { ok: true, room: { width, height, biome: template.biome, seed, attempt: attempt + 1, cells } };
  }
  return { ok: false, error: `WFC reached a contradiction in all ${template.maxAttempts} attempts. Review tile sockets or pins.`, attempts: template.maxAttempts };
}
