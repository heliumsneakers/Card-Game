import { useMemo, useState } from "react";
import {
  catalogBiomes,
  defaultRoomTemplate,
  defaultTileCatalog,
  tileImageUrl,
  type Direction,
  type RoomTemplate,
  type TileLayer,
  type TileMetadata,
} from "./tileCatalog";
import { generateRoom, type GeneratedRoom, type WfcResult } from "./wfc";

const roomDraftKey = "cardgame.room-builder.draft.v1";
const directions: Direction[] = ["north", "east", "south", "west"];

interface RoomBuilderDraft {
  catalog: TileMetadata[];
  template: RoomTemplate;
  seed: number;
}

function clone<T>(value: T): T { return JSON.parse(JSON.stringify(value)) as T; }

function loadDraft(): RoomBuilderDraft {
  try {
    const stored = localStorage.getItem(roomDraftKey);
    if (stored) return JSON.parse(stored) as RoomBuilderDraft;
  } catch { /* Fall back to the reviewed built-in catalog. */ }
  return { catalog: clone(defaultTileCatalog), template: clone(defaultRoomTemplate), seed: 4815 };
}

function saveDraft(draft: RoomBuilderDraft): void {
  localStorage.setItem(roomDraftKey, JSON.stringify(draft));
}

function downloadJson(filename: string, value: unknown): void {
  const url = URL.createObjectURL(new Blob([`${JSON.stringify(value, null, 2)}\n`], { type: "application/json" }));
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

function TileSprite({ tile, className = "" }: { tile: TileMetadata; className?: string }) {
  return <img className={className} src={tileImageUrl(tile)} alt="" draggable={false} />;
}

function TileCatalogEditor({ draft, onChange }: { draft: RoomBuilderDraft; onChange: (draft: RoomBuilderDraft) => void }) {
  const [layer, setLayer] = useState<TileLayer | "all">("all");
  const [biome, setBiome] = useState("all");
  const [selectedId, setSelectedId] = useState(draft.catalog[0]?.id || "");
  const selected = draft.catalog.find((tile) => tile.id === selectedId) || draft.catalog[0];
  const filtered = draft.catalog.filter((tile) => (layer === "all" || tile.layer === layer) && (biome === "all" || tile.biomes.includes(biome)));

  const updateTile = (tile: TileMetadata) => {
    onChange({ ...draft, catalog: draft.catalog.map((candidate) => candidate.id === tile.id ? tile : candidate) });
  };

  return <>
    <div className="section-heading"><div><span>WFC metadata</span><h1>Isometric Tile Catalog</h1></div><div className="power-chip">{draft.catalog.length} SPRITES</div></div>
    <section className="panel"><div className="panel-title"><div><h2>Reviewed asset labels</h2><p>Terrain participates in WFC. Objects and effects are placed in later passes.</p></div></div>
      <div className="tile-filters"><label><span>Layer</span><select value={layer} onChange={(event) => setLayer(event.target.value as TileLayer | "all")}><option value="all">All layers</option><option value="terrain">Terrain</option><option value="object">Objects</option><option value="effect">Effects</option></select></label><label><span>Biome</span><select value={biome} onChange={(event) => setBiome(event.target.value)}><option value="all">All biomes</option>{catalogBiomes(draft.catalog).map((name) => <option key={name}>{name}</option>)}</select></label><button type="button" onClick={() => { const next = { ...draft, catalog: clone(defaultTileCatalog) }; saveDraft(next); onChange(next); setSelectedId(next.catalog[0].id); }}>Reset labels</button></div>
      <div className="tile-catalog-grid">{filtered.map((tile) => <button type="button" key={tile.id} className={tile.id === selected?.id ? "selected" : ""} onClick={() => setSelectedId(tile.id)} title={`${tile.sourceIndex}: ${tile.name}`}><TileSprite tile={tile} /><small>{String(tile.sourceIndex).padStart(3, "0")}</small></button>)}</div>
    </section>
    {selected && <section className="panel tile-inspector"><div className="tile-inspector-heading"><div className="sprite-well"><TileSprite tile={selected} /></div><div><span>tile_{String(selected.sourceIndex).padStart(3, "0")}.png</span><h2>{selected.name}</h2><code>{selected.id}</code></div></div>
      <div className="field-grid">
        <label><span>Label</span><input value={selected.name} onChange={(event) => updateTile({ ...selected, name: event.target.value })} /></label>
        <label><span>Layer</span><select value={selected.layer} onChange={(event) => updateTile({ ...selected, layer: event.target.value as TileLayer })}><option value="terrain">Terrain (WFC)</option><option value="object">Object overlay</option><option value="effect">Effect overlay</option></select></label>
        <label><span>Category</span><input value={selected.category} onChange={(event) => updateTile({ ...selected, category: event.target.value.trim().toLowerCase().replace(/\s+/g, "_") })} /></label>
        <label><span>Biomes</span><input value={selected.biomes.join(", ")} onChange={(event) => updateTile({ ...selected, biomes: event.target.value.split(",").map((value) => value.trim().toLowerCase()).filter(Boolean) })} /></label>
        <label><span>Selection weight</span><input type="number" min="0.01" step="0.1" value={selected.weight} onChange={(event) => updateTile({ ...selected, weight: Number(event.target.value) })} /></label>
        <label><span>Tags</span><input value={selected.tags.join(", ")} onChange={(event) => updateTile({ ...selected, tags: event.target.value.split(",").map((value) => value.trim().toLowerCase()).filter(Boolean) })} /></label>
        <label className="check"><input type="checkbox" checked={selected.enabled} onChange={(event) => updateTile({ ...selected, enabled: event.target.checked })} /> Enabled</label>
        <label className="check"><input type="checkbox" checked={selected.walkable} onChange={(event) => updateTile({ ...selected, walkable: event.target.checked })} /> Walkable</label>
        <label className="check"><input type="checkbox" checked={selected.blocksSight} onChange={(event) => updateTile({ ...selected, blocksSight: event.target.checked })} /> Blocks sight</label>
      </div>
      <h3 className="socket-heading">Adjacency sockets</h3><div className="socket-grid">{directions.map((direction) => <label key={direction}><span>{direction}</span><input value={selected.sockets[direction]} onChange={(event) => updateTile({ ...selected, sockets: { ...selected.sockets, [direction]: event.target.value.trim().toLowerCase() } })} /></label>)}</div>
    </section>}
  </>;
}

function IsometricRoomPreview({ room, catalog, pins, onTogglePin }: { room: GeneratedRoom; catalog: TileMetadata[]; pins: RoomTemplate["pins"]; onTogglePin: (x: number, y: number, tileId: string) => void }) {
  const tiles = useMemo(() => new Map(catalog.map((tile) => [tile.id, tile])), [catalog]);
  const scale = 2;
  const stepX = 16 * scale;
  const stepY = 8 * scale;
  const spriteSize = 32 * scale;
  const width = (room.width + room.height) * stepX + spriteSize;
  const height = (room.width + room.height) * stepY + spriteSize + 28;
  const center = room.height * stepX;
  return <div className="iso-scroll"><div className="iso-room" style={{ width, height }}>
    {[...room.cells].sort((a, b) => (a.x + a.y) - (b.x + b.y) || a.y - b.y).map((cell) => {
      const tile = tiles.get(cell.tileId);
      const object = cell.objectId ? tiles.get(cell.objectId) : undefined;
      const pinned = pins.some((pin) => pin.x === cell.x && pin.y === cell.y);
      if (!tile) return null;
      return <button type="button" className={`iso-cell ${pinned ? "pinned" : ""}`} key={`${cell.x}:${cell.y}`} style={{ left: center + (cell.x - cell.y) * stepX, top: (cell.x + cell.y) * stepY, width: spriteSize, height: spriteSize, zIndex: 1 + cell.x + cell.y }} title={`${cell.x}, ${cell.y} · ${tile.name}${pinned ? " · pinned" : ""}`} onClick={() => onTogglePin(cell.x, cell.y, cell.tileId)}>
        <TileSprite tile={tile} />
        {object && <TileSprite tile={object} className="iso-object" />}
        {cell.enemySpawn && <span className="spawn-marker">E</span>}
      </button>;
    })}
  </div></div>;
}

function TemplateBuilder({ draft, onChange }: { draft: RoomBuilderDraft; onChange: (draft: RoomBuilderDraft) => void }) {
  const [result, setResult] = useState<WfcResult>(() => generateRoom(draft.catalog, draft.template, draft.seed));
  const template = draft.template;
  const setTemplate = (next: RoomTemplate) => onChange({ ...draft, template: next });
  const generate = () => setResult(generateRoom(draft.catalog, draft.template, draft.seed));
  const room = result.ok ? result.room : undefined;
  const generationError = result.ok ? undefined : result.error;

  const togglePin = (x: number, y: number, tileId: string) => {
    const existing = template.pins.some((pin) => pin.x === x && pin.y === y);
    setTemplate({ ...template, pins: existing ? template.pins.filter((pin) => pin.x !== x || pin.y !== y) : [...template.pins, { x, y, tileId }] });
  };

  const numberField = (key: keyof Pick<RoomTemplate, "minWidth" | "maxWidth" | "minHeight" | "maxHeight" | "objectDensity" | "minimumEnemySpawns" | "maximumEnemySpawns" | "maxAttempts">, value: number) => setTemplate({ ...template, [key]: value });

  return <>
    <div className="section-heading"><div><span>Procedural rooms</span><h1>Room Template Builder</h1></div><div className="section-actions"><div className="power-chip">{template.pins.length} PINS</div><button type="button" className="builder-button" onClick={() => downloadJson("room-generation.json", { schemaVersion: 1, catalog: draft.catalog, templates: [template], generatedRoom: room })}>Export Room JSON</button></div></div>
    <section className="panel fields"><div className="panel-title"><div><h2>Template constraints</h2><p>The seed chooses fixed dimensions within these bounds, then WFC collapses compatible biome tiles.</p></div></div><div className="field-grid">
      <label><span>Template name</span><input value={template.name} onChange={(event) => setTemplate({ ...template, name: event.target.value })} /></label>
      <label><span>Biome</span><select value={template.biome} onChange={(event) => setTemplate({ ...template, biome: event.target.value, pins: [] })}>{catalogBiomes(draft.catalog).filter((name) => draft.catalog.some((tile) => tile.layer === "terrain" && tile.biomes.includes(name))).map((name) => <option key={name}>{name}</option>)}</select></label>
      <label><span>Minimum width</span><input type="number" min="1" max={template.maxWidth} value={template.minWidth} onChange={(event) => numberField("minWidth", Number(event.target.value))} /></label>
      <label><span>Maximum width</span><input type="number" min={template.minWidth} max="24" value={template.maxWidth} onChange={(event) => numberField("maxWidth", Number(event.target.value))} /></label>
      <label><span>Minimum height</span><input type="number" min="1" max={template.maxHeight} value={template.minHeight} onChange={(event) => numberField("minHeight", Number(event.target.value))} /></label>
      <label><span>Maximum height</span><input type="number" min={template.minHeight} max="24" value={template.maxHeight} onChange={(event) => numberField("maxHeight", Number(event.target.value))} /></label>
      <label><span>Object density</span><div className="input-suffix"><input type="number" min="0" max="100" value={Math.round(template.objectDensity * 100)} onChange={(event) => numberField("objectDensity", Number(event.target.value) / 100)} /><span>%</span></div></label>
      <label><span>WFC retry limit</span><input type="number" min="1" max="100" value={template.maxAttempts} onChange={(event) => numberField("maxAttempts", Number(event.target.value))} /></label>
      <label><span>Minimum enemy spawns</span><input type="number" min="0" max={template.maximumEnemySpawns} value={template.minimumEnemySpawns} onChange={(event) => numberField("minimumEnemySpawns", Number(event.target.value))} /></label>
      <label><span>Maximum enemy spawns</span><input type="number" min={template.minimumEnemySpawns} max="16" value={template.maximumEnemySpawns} onChange={(event) => numberField("maximumEnemySpawns", Number(event.target.value))} /></label>
    </div></section>
    <section className="panel"><div className="generator-toolbar"><label><span>Generation seed</span><input type="number" value={draft.seed} onChange={(event) => onChange({ ...draft, seed: Number(event.target.value) })} /></label><button type="button" onClick={() => onChange({ ...draft, seed: Math.floor(Math.random() * 2147483646) + 1 })}>Random seed</button><button type="button" disabled={template.pins.length === 0} onClick={() => setTemplate({ ...template, pins: [] })}>Clear pins</button><button type="button" className="primary" onClick={generate}>Generate room</button></div>
      {room ? <><div className="generation-summary"><span>{room.width} × {room.height}</span><span>{room.biome}</span><span>Attempt {room.attempt}/{template.maxAttempts}</span><span>{room.cells.filter((cell) => cell.enemySpawn).length} enemy spawns</span></div><p className="pin-help">Click a generated cell to pin or unpin that exact tile, then generate again.</p><IsometricRoomPreview room={room} catalog={draft.catalog} pins={template.pins} onTogglePin={togglePin} /></> : <div className="generation-error"><b>Generation failed</b><span>{generationError}</span></div>}
    </section>
  </>;
}

export function RoomBuilder({ mode }: { mode: "catalog" | "builder" }) {
  const [draft, setDraft] = useState<RoomBuilderDraft>(loadDraft);
  const update = (next: RoomBuilderDraft) => { setDraft(next); saveDraft(next); };
  return mode === "catalog" ? <TileCatalogEditor draft={draft} onChange={update} /> : <TemplateBuilder draft={draft} onChange={update} />;
}
