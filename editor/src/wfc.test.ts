import { describe, expect, it } from "vitest";
import { defaultRoomTemplate, defaultTileCatalog, type TileMetadata } from "./tileCatalog";
import { generateRoom } from "./wfc";

describe("simple tiled WFC", () => {
  it("generates deterministic rooms inside the configured size range", () => {
    const first = generateRoom(defaultTileCatalog, defaultRoomTemplate, 4815);
    const second = generateRoom(defaultTileCatalog, defaultRoomTemplate, 4815);
    expect(first).toEqual(second);
    expect(first.ok).toBe(true);
    if (!first.ok) return;
    expect(first.room.width).toBeGreaterThanOrEqual(defaultRoomTemplate.minWidth);
    expect(first.room.width).toBeLessThanOrEqual(defaultRoomTemplate.maxWidth);
    expect(first.room.height).toBeGreaterThanOrEqual(defaultRoomTemplate.minHeight);
    expect(first.room.height).toBeLessThanOrEqual(defaultRoomTemplate.maxHeight);
    expect(first.room.cells).toHaveLength(first.room.width * first.room.height);
  });

  it("respects pinned cells", () => {
    const tile = defaultTileCatalog.find((candidate) => candidate.layer === "terrain" && candidate.biomes.includes("forest"))!;
    const template = { ...defaultRoomTemplate, minWidth: 5, maxWidth: 5, minHeight: 5, maxHeight: 5, pins: [{ x: 2, y: 3, tileId: tile.id }] };
    const result = generateRoom(defaultTileCatalog, template, 7);
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.room.cells.find((cell) => cell.x === 2 && cell.y === 3)?.tileId).toBe(tile.id);
  });

  it("reports a contradiction when pinned socket rules cannot be satisfied", () => {
    const makeTile = (id: string, socket: string): TileMetadata => ({
      id, name: id, source: "", sourceIndex: 0, category: "test", layer: "terrain", biomes: ["test"],
      sockets: { north: socket, east: socket, south: socket, west: socket }, walkable: true,
      blocksSight: false, weight: 1, enabled: true, tags: [],
    });
    const catalog = [makeTile("tile.a", "a"), makeTile("tile.b", "b")];
    const result = generateRoom(catalog, {
      ...defaultRoomTemplate, biome: "test", minWidth: 2, maxWidth: 2, minHeight: 1, maxHeight: 1,
      maxAttempts: 2, pins: [{ x: 0, y: 0, tileId: "tile.a" }, { x: 1, y: 0, tileId: "tile.b" }],
    }, 1);
    expect(result.ok).toBe(false);
  });

  it("rejects invalid room bounds before attempting a collapse", () => {
    const result = generateRoom(defaultTileCatalog, { ...defaultRoomTemplate, minWidth: 9, maxWidth: 5 }, 1);
    expect(result).toEqual({ ok: false, error: "Width bounds must be positive whole numbers, with maximum width at least minimum width.", attempts: 0 });
  });
});
