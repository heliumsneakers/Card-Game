export type Direction = "north" | "east" | "south" | "west";
export type TileLayer = "terrain" | "object" | "effect";

export interface TileMetadata {
  id: string;
  name: string;
  source: string;
  sourceIndex: number;
  category: string;
  layer: TileLayer;
  biomes: string[];
  sockets: Record<Direction, string>;
  walkable: boolean;
  blocksSight: boolean;
  weight: number;
  enabled: boolean;
  tags: string[];
}

export interface RoomPin {
  x: number;
  y: number;
  tileId: string;
}

export interface RoomTemplate {
  id: string;
  name: string;
  biome: string;
  minWidth: number;
  maxWidth: number;
  minHeight: number;
  maxHeight: number;
  objectDensity: number;
  minimumEnemySpawns: number;
  maximumEnemySpawns: number;
  maxAttempts: number;
  pins: RoomPin[];
}

interface CatalogGroup {
  start: number;
  end: number;
  label: string;
  category: string;
  layer: TileLayer;
  biomes: string[];
  socket: string;
  walkable?: boolean;
  blocksSight?: boolean;
  tags: string[];
}

const groups: CatalogGroup[] = [
  { start: 0, end: 10, label: "Dry earth plateau", category: "earth", layer: "terrain", biomes: ["badlands"], socket: "badlands_ground", walkable: true, tags: ["ground", "soil"] },
  { start: 11, end: 21, label: "Rocky earth plateau", category: "earth", layer: "terrain", biomes: ["badlands"], socket: "badlands_ground", walkable: true, tags: ["ground", "rocky"] },
  { start: 22, end: 24, label: "Grass clearing", category: "grass", layer: "terrain", biomes: ["forest"], socket: "forest_ground", walkable: true, tags: ["ground", "grass"] },
  { start: 25, end: 26, label: "Mossy earth", category: "grass", layer: "terrain", biomes: ["forest"], socket: "forest_ground", walkable: true, tags: ["ground", "moss"] },
  { start: 27, end: 36, label: "Dense foliage", category: "foliage", layer: "object", biomes: ["forest"], socket: "overlay", blocksSight: true, tags: ["foliage", "dense"] },
  { start: 37, end: 40, label: "Soft grass clearing", category: "grass", layer: "terrain", biomes: ["forest"], socket: "forest_ground", walkable: true, tags: ["ground", "grass"] },
  { start: 41, end: 47, label: "Wildflower patch", category: "flora", layer: "object", biomes: ["forest"], socket: "overlay", tags: ["decoration", "flowers"] },
  { start: 48, end: 52, label: "Fallen timber", category: "timber", layer: "object", biomes: ["forest"], socket: "overlay", blocksSight: true, tags: ["obstacle", "wood"] },
  { start: 53, end: 60, label: "Brown rock formation", category: "rock", layer: "object", biomes: ["badlands", "forest"], socket: "overlay", blocksSight: true, tags: ["obstacle", "rock"] },
  { start: 61, end: 67, label: "Gray rock formation", category: "rock", layer: "object", biomes: ["badlands", "winter"], socket: "overlay", blocksSight: true, tags: ["obstacle", "rock"] },
  { start: 68, end: 81, label: "Water rock formation", category: "water_rock", layer: "object", biomes: ["water"], socket: "overlay", blocksSight: true, tags: ["obstacle", "rock", "water"] },
  { start: 82, end: 87, label: "Water ripple", category: "water_detail", layer: "effect", biomes: ["water"], socket: "overlay", tags: ["decoration", "water"] },
  { start: 88, end: 109, label: "Deep water", category: "water", layer: "terrain", biomes: ["water"], socket: "water", tags: ["ground", "water"] },
  { start: 110, end: 114, label: "Ice field", category: "ice", layer: "terrain", biomes: ["winter"], socket: "ice_ground", walkable: true, tags: ["ground", "ice"] },
];

const specialNames: Record<number, string> = {
  36: "Tall grass clump",
  41: "Orange flower patch",
  42: "Mixed flower patch",
  43: "Leafy grass clump",
  44: "Purple flower cluster",
  45: "Fern clump",
  46: "Red and yellow flowers",
  47: "Scattered flower petals",
  48: "Cut log",
  49: "Broken branches",
  50: "Fallen log",
  51: "Mossy fallen log",
  52: "Tree stump",
};

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
}

function padded(index: number): string {
  return String(index).padStart(3, "0");
}

export const defaultTileCatalog: TileMetadata[] = groups.flatMap((group) => {
  const tiles: TileMetadata[] = [];
  for (let index = group.start; index <= group.end; index += 1) {
    const sequence = index - group.start + 1;
    const name = specialNames[index] || `${group.label} ${String(sequence).padStart(2, "0")}`;
    tiles.push({
      id: `tile.${slug(name)}_${padded(index)}`,
      name,
      source: `tiles/isometric/tile_${padded(index)}.png`,
      sourceIndex: index,
      category: group.category,
      layer: group.layer,
      biomes: [...group.biomes],
      sockets: { north: group.socket, east: group.socket, south: group.socket, west: group.socket },
      walkable: group.walkable ?? false,
      blocksSight: group.blocksSight ?? false,
      weight: 1,
      enabled: true,
      tags: [...group.tags],
    });
  }
  return tiles;
});

export const defaultRoomTemplate: RoomTemplate = {
  id: "room_template.forest_combat",
  name: "Forest Combat Room",
  biome: "forest",
  minWidth: 5,
  maxWidth: 8,
  minHeight: 5,
  maxHeight: 8,
  objectDensity: 0.12,
  minimumEnemySpawns: 1,
  maximumEnemySpawns: 4,
  maxAttempts: 20,
  pins: [],
};

export function tileImageUrl(tile: Pick<TileMetadata, "source">): string {
  return `${import.meta.env.BASE_URL}${tile.source.split("/").map(encodeURIComponent).join("/")}`;
}

export function catalogBiomes(catalog: TileMetadata[]): string[] {
  return [...new Set(catalog.flatMap((tile) => tile.biomes))].sort();
}
