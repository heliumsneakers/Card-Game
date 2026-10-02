import { ExecutionPreview } from "./ExecutionPreview";
import { AuthoringCards } from "./AuthoringContext";
import { replaceCard } from "./effects/references";
import { useEffect, useMemo, useRef, useState } from "react";
import initial from "../../game/content/content.json";
import { DescriptionEditor } from "./DescriptionEditor";
import { EffectEditor } from "./EffectEditor";
import { RoomBuilder } from "./RoomBuilder";
import { contentId, describeCard, deterministicJson, encounterCandidates, enemyPower, migrateDescriptions, removeCard, validateContent } from "./content";
import { literal, type CardDefinition, type ContentDocument, type EnemyDefinition, type RoomDefinition } from "./model";

type Selection =
  | { kind: "card" | "enemy"; id: string }
  | { kind: "room"; id: number }
  | { kind: "endless"; id: "endless" }
  | { kind: "world"; id: "catalog" | "builder" };
const draftKey = "cardgame.editor.draft.v1";

// Copy imported data so editor updates never mutate the bundled catalog.
function clone<T>(value: T): T { return JSON.parse(JSON.stringify(value)) as T; }
// Choose the first available catalog entry for a new draft.
function initialSelection(content: ContentDocument): Selection {
  if (content.cards[0]) return { kind: "card", id: content.cards[0].id };
  if (content.enemies[0]) return { kind: "enemy", id: content.enemies[0].id };
  return { kind: "card", id: "" };
}

// Coordinate catalog editing, draft persistence, and the embedded game preview.
export default function App() {
  const gameUrl = `${import.meta.env.BASE_URL}game/index.html`;
  const [content, setContent] = useState<ContentDocument>(() => {
    // Browser drafts take precedence over bundled content.
    const saved = localStorage.getItem(draftKey);
    return migrateDescriptions(saved ? JSON.parse(saved) as ContentDocument : clone(initial as ContentDocument));
  });
  const [selection, setSelection] = useState<Selection>(() => initialSelection(content));
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("Draft loaded");
  const [previewRunning, setPreviewRunning] = useState(false);
  const [previewInstance, setPreviewInstance] = useState(0);
  const importRef = useRef<HTMLInputElement>(null);
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const issues = useMemo(() => validateContent(content), [content]);
  const selectedCard = selection.kind === "card" ? content.cards.find((item) => item.id === selection.id) : undefined;
  const selectedEnemy = selection.kind === "enemy" ? content.enemies.find((item) => item.id === selection.id) : undefined;
  const selectedRoom = selection.kind === "room" ? content.roomCurve.find((item) => item.room === selection.id) : undefined;
  const selectedEndless = selection.kind === "endless" ? content.endless : undefined;
  const selectedRoomCandidates = useMemo(() => {
    if (!selectedRoom) return [];
    const lower = selectedRoom.power * selectedRoom.minimumBudgetRatio;
    const upper = selectedRoom.power * selectedRoom.maximumBudgetRatio;
    return encounterCandidates(content, selectedRoom).filter((candidate) => candidate.power >= lower && candidate.power <= upper);
  }, [content, selectedRoom]);

  useEffect(() => { localStorage.setItem(draftKey, JSON.stringify(content)); }, [content]);
  useEffect(() => {
    // Accept preview acknowledgements only from the local editor origin.
    const listener = (event: MessageEvent) => {
      if (event.origin !== window.location.origin || !event.data) return;
      if (event.data.type === "cardgame.content.result") {
        setStatus(event.data.ok
          ? `Preview loaded ${event.data.featuredCardId || event.data.revision || "this draft"}`
          : `Preview rejected: ${(event.data.errors || []).join(", ")}`);
      }
    };
    window.addEventListener("message", listener);
    return () => window.removeEventListener("message", listener);
  }, []);

  // Keep counter readers and writers connected when a card is renamed.
  const updateCard = (card: CardDefinition) => {
    const previousId = String(selection.id);
    // Keep the old identity while a name temporarily collides during typing.
    if (content.cards.some((item) => item.id === card.id && item.id !== previousId)) card = { ...card, id: previousId };
    setContent((current) => replaceCard(current, previousId, card));
    if (card.id !== previousId) setSelection({ kind: "card", id: card.id });
  };
  // Replace the selected enemy and keep its derived selection in sync.
  const updateEnemy = (enemy: EnemyDefinition) => {
    // Name edits can change the derived enemy ID.
    const previousId = selection.id;
    setContent((current) => ({ ...current, enemies: current.enemies.map((item) => item.id === previousId ? enemy : item), contentRevision: `draft-${Date.now()}` }));
    if (enemy.id !== previousId) setSelection({ kind: "enemy", id: enemy.id });
  };
  // Update one encounter setting without replacing other rooms.
  const updateRoom = (room: RoomDefinition) => {
    setContent((current) => ({ ...current, roomCurve: current.roomCurve.map((item) => item.room === room.room ? room : item), contentRevision: `draft-${Date.now()}` }));
  };
  // Store endless-mode settings with a new draft revision.
  const updateEndless = (endless: ContentDocument["endless"]) => {
    setContent((current) => ({ ...current, endless, contentRevision: `draft-${Date.now()}` }));
  };

  // Create a uniquely named card with a simple editable damage block.
  const addCard = () => {
    // Reserve a free name before building its derived ID.
    let name = "New Card"; let suffix = 2;
    while (content.cards.some((card) => card.id === contentId("card", name))) name = `New Card ${suffix++}`;
    const id = contentId("card", name);
    const card: CardDefinition = { id, name, cost: 1, type: "DMG", element: "fire", target: "enemy", enabled: true, description: "Deal {dmg=2} damage to target.", availability: { startingDeck: 0, shop: true, shopChance: 50, copyLimit: 3 }, effects: [{ op: "damage", target: "selectedEnemy", amount: literal(2), scalable: true }] };
    setContent({ ...content, cards: [...content.cards, card] }); setSelection({ kind: "card", id });
  };
  // Create an enemy with valid combat and encounter defaults.
  const addEnemy = () => {
    // Avoid duplicate identities in the current catalog.
    let name = "New Enemy"; let suffix = 2;
    while (content.enemies.some((enemy) => enemy.id === contentId("enemy", name))) name = `New Enemy ${suffix++}`;
    const id = contentId("enemy", name);
    const enemy: EnemyDefinition = {
      id, name, damage: { min: 2, max: 3 }, hp: { min: 8, max: 10 }, enabled: true,
      generation: { spawnEnabled: true, spawnWeight: 1, minimumRoom: 1, maximumCopies: 4, bossOnly: false, tags: [] },
    };
    setContent({ ...content, enemies: [...content.enemies, enemy] }); setSelection({ kind: "enemy", id });
  };
  // Remove the selected card and choose the nearest remaining entry.
  const deleteSelectedCard = () => {
    if (!selectedCard || !window.confirm(`Delete "${selectedCard.name || "Untitled card"}"? This cannot be undone.`)) return;
    // Preserve a useful selection after removal.
    const deletedIndex = content.cards.findIndex((card) => card.id === selectedCard.id);
    const nextContent = removeCard(content, selectedCard.id);
    const nextCard = nextContent.cards[Math.min(deletedIndex, nextContent.cards.length - 1)];
    setContent(nextContent);
    if (nextCard) setSelection({ kind: "card", id: nextCard.id });
    else if (nextContent.enemies[0]) setSelection({ kind: "enemy", id: nextContent.enemies[0].id });
    else setSelection({ kind: "card", id: "" });
    setStatus(`Deleted ${selectedCard.name || selectedCard.id}`);
  };
  // Download only drafts that pass content and effect validation.
  const exportJson = () => {
    if (issues.length) { setStatus("Fix validation issues before exporting"); return; }
    // Revoke the temporary download URL immediately after dispatch.
    const url = URL.createObjectURL(new Blob([deterministicJson(content)], { type: "application/json" }));
    const anchor = document.createElement("a"); anchor.href = url; anchor.download = "content.json"; anchor.click(); URL.revokeObjectURL(url); setStatus("Exported content.json");
  };
  // Migrate and validate imported JSON before replacing the draft.
  const importJson = async (file?: File) => {
    if (!file) return;
    // Invalid imports leave the existing draft intact.
    try { const next = migrateDescriptions(JSON.parse(await file.text()) as ContentDocument); const nextIssues = validateContent(next); if (nextIssues.length) throw new Error(nextIssues[0].message); setContent(next); setSelection(initialSelection(next)); setStatus(`Imported ${file.name}`); }
    catch (error) { setStatus(`Import failed: ${error instanceof Error ? error.message : String(error)}`); }
  };
  // Pass a validated snapshot to a fresh embedded game instance.
  const loadPreview = (nextStatus: string) => {
    if (issues.length) { setStatus("Fix validation issues before previewing"); return; }
    // The featured card is available in the preview opening hand.
    const previewContent = { ...content, preview: { featuredCardId: selectedCard?.id } };
    localStorage.setItem("cardgame.preview.content", deterministicJson(previewContent));
    setStatus(nextStatus);
    setPreviewRunning(true);
    setPreviewInstance((current) => current + 1);
  };
  // Reload the embedded game with the current authored snapshot.
  const applyPreview = () => loadPreview(previewRunning ? "Reloading preview…" : "Starting preview…");
  // Unmount the embedded game while keeping the editor draft.
  const stopPreview = () => {
    setPreviewRunning(false);
    setStatus("Preview stopped");
  };

  const filteredCards = content.cards.filter((card) => card.name.toLowerCase().includes(query.toLowerCase()));
  const filteredEnemies = content.enemies.filter((enemy) => enemy.name.toLowerCase().includes(query.toLowerCase()));

  return <AuthoringCards.Provider value={content.cards}><div className="app-shell">
    <header className="topbar"><div className="brand"><span className="brand-mark">CF</span><div><b>Card Forge</b><small>Content editor</small></div></div><div className={`validation ${issues.length ? "invalid" : "valid"}`}>{issues.length ? `${issues.length} issue${issues.length === 1 ? "" : "s"}` : "Ready to preview"}</div><div className="top-actions"><button onClick={() => importRef.current?.click()}>Import</button><input ref={importRef} hidden type="file" accept="application/json" onChange={(event) => importJson(event.target.files?.[0])} /><button onClick={exportJson}>Export JSON</button><button className="primary" onClick={applyPreview}>Apply to Preview</button></div></header>
    <aside className="catalog"><div className="catalog-tools"><input aria-label="Search content" placeholder="Search content…" value={query} onChange={(event) => setQuery(event.target.value)} /><div><button onClick={addCard}>+ Card</button><button onClick={addEnemy}>+ Enemy</button></div></div><h2>World tools</h2><button className={`catalog-item ${selection.kind === "world" && selection.id === "catalog" ? "selected" : ""}`} onClick={() => setSelection({ kind: "world", id: "catalog" })}><i className="type-dot tiles" /><span><b>Tile catalog</b><small>115 labeled isometric sprites</small></span></button><button className={`catalog-item ${selection.kind === "world" && selection.id === "builder" ? "selected" : ""}`} onClick={() => setSelection({ kind: "world", id: "builder" })}><i className="type-dot generator" /><span><b>Room builder</b><small>WFC templates and preview</small></span></button><h2>Cards <span>{content.cards.length}</span></h2>{filteredCards.map((card) => <button className={`catalog-item ${selection.kind === "card" && selection.id === card.id ? "selected" : ""}`} key={card.id} onClick={() => setSelection({ kind: "card", id: card.id })}><i className={`type-dot element-${card.element}`} /><span><b>{card.name}</b><small>{card.cost} mana · {card.type} · {card.element}</small></span></button>)}<h2>Enemies <span>{content.enemies.length}</span></h2>{filteredEnemies.map((enemy) => <button className={`catalog-item ${selection.kind === "enemy" && selection.id === enemy.id ? "selected" : ""}`} key={enemy.id} onClick={() => setSelection({ kind: "enemy", id: enemy.id })}><i className="type-dot enemy" /><span><b>{enemy.name}</b><small>Power {enemyPower(enemy).toFixed(2)} · {enemy.damage.min}–{enemy.damage.max} ATK</small></span></button>)}<h2>Encounter curve</h2>{content.roomCurve.map((room) => <button className={`catalog-item ${selection.kind === "room" && selection.id === room.room ? "selected" : ""}`} key={room.room} onClick={() => setSelection({ kind: "room", id: room.room })}><i className="type-dot room" /><span><b>Room {room.room}</b><small>Power {room.power} · {room.minimumEnemies}–{room.maximumEnemies} enemies</small></span></button>)}<button className={`catalog-item ${selection.kind === "endless" ? "selected" : ""}`} onClick={() => setSelection({ kind: "endless", id: "endless" })}><i className="type-dot endless" /><span><b>Endless mode</b><small>Starts at {content.endless.startingPower} · +{content.endless.powerPerRoom} power</small></span></button></aside>
    <main className="inspector">
      {selectedCard && <><div className="section-heading"><div><span>Card definition</span><h1>{selectedCard.name || "Untitled card"}</h1></div><div className="section-actions"><div className="card-chip">{selectedCard.type}</div><div className={`card-chip element-${selectedCard.element}`}>{selectedCard.element}</div><button type="button" className="delete-button" onClick={deleteSelectedCard}>Delete Card</button></div></div><section className="panel fields"><h2>Identity</h2><div className="field-grid"><label><span>Name</span><input value={selectedCard.name} onChange={(event) => { const name = event.target.value; updateCard({ ...selectedCard, name, id: contentId("card", name) }); }} /></label><label><span>Stable ID</span><input className="derived-id" value={selectedCard.id} readOnly aria-readonly="true" title="Generated automatically from the card name" /></label><label><span>Mana cost</span><input type="number" min="0" value={selectedCard.cost} onChange={(event) => updateCard({ ...selectedCard, cost: Number(event.target.value) })} /></label><label><span>Category</span><select value={selectedCard.type} onChange={(event) => updateCard({ ...selectedCard, type: event.target.value as CardDefinition["type"] })}><option>DMG</option><option>DEF</option><option>HEAL</option><option>UTIL</option></select></label><label><span>Element</span><select value={selectedCard.element} onChange={(event) => updateCard({ ...selectedCard, element: event.target.value as CardDefinition["element"] })}><option value="fire">Fire</option><option value="ice">Ice</option><option value="nature">Nature</option><option value="earth">Earth</option><option value="arcane">Arcane</option></select></label><label><span>Target</span><select value={selectedCard.target} onChange={(event) => updateCard({ ...selectedCard, target: event.target.value as CardDefinition["target"] })}><option value="enemy">One Enemy</option><option value="multi">Multiple Enemies</option><option value="all">All Enemies</option><option value="self">Self</option></select></label><label className="check"><input type="checkbox" checked={selectedCard.availability.shop} onChange={(event) => updateCard({ ...selectedCard, availability: { ...selectedCard.availability, shop: event.target.checked } })} /> Available in shop</label><label><span>Shop appearance chance</span><div className="input-suffix"><input type="number" min="0" max="100" step="1" disabled={!selectedCard.availability.shop} value={selectedCard.availability.shopChance} onChange={(event) => updateCard({ ...selectedCard, availability: { ...selectedCard.availability, shopChance: Number(event.target.value) } })} /><span>%</span></div></label><label><span>Deck copy limit</span><input type="number" min="1" value={selectedCard.availability.copyLimit} onChange={(event) => updateCard({ ...selectedCard, availability: { ...selectedCard.availability, copyLimit: Number(event.target.value) } })} /></label></div></section><section className="panel"><div className="panel-title"><div><h2>Rules text</h2><p>Handwrite the description and place live values exactly where you want them.</p></div></div><DescriptionEditor description={selectedCard.description} effects={selectedCard.effects} onChange={(description) => updateCard({ ...selectedCard, description })} /></section><section className="panel"><div className="panel-title"><div><h2>Effect blocks</h2><p>Effects resolve from top to bottom and supply the live values used above.</p></div></div><EffectEditor effects={selectedCard.effects} onChange={(effects) => updateCard({ ...selectedCard, effects })} /></section><ExecutionPreview card={selectedCard} cards={content.cards} /></>}
      {selectedEnemy && <>
        <div className="section-heading"><div><span>Enemy definition</span><h1>{selectedEnemy.name || "Untitled enemy"}</h1></div><div className="section-actions"><div className="power-chip">POWER {enemyPower(selectedEnemy).toFixed(2)}</div><div className="card-chip enemy">ENEMY</div></div></div>
        <section className="panel fields"><h2>Identity & stats</h2><div className="field-grid">
          <label><span>Name</span><input value={selectedEnemy.name} onChange={(event) => { const name = event.target.value; updateEnemy({ ...selectedEnemy, name, id: contentId("enemy", name) }); }} /></label>
          <label><span>Stable ID</span><input className="derived-id" value={selectedEnemy.id} readOnly aria-readonly="true" title="Generated automatically from the enemy name" /></label>
          <label><span>Damage minimum</span><input type="number" min="0" value={selectedEnemy.damage.min} onChange={(event) => updateEnemy({ ...selectedEnemy, damage: { ...selectedEnemy.damage, min: Number(event.target.value) } })} /></label>
          <label><span>Damage maximum</span><input type="number" min="0" value={selectedEnemy.damage.max} onChange={(event) => updateEnemy({ ...selectedEnemy, damage: { ...selectedEnemy.damage, max: Number(event.target.value) } })} /></label>
          <label><span>HP minimum</span><input type="number" min="1" value={selectedEnemy.hp.min} onChange={(event) => updateEnemy({ ...selectedEnemy, hp: { ...selectedEnemy.hp, min: Number(event.target.value) } })} /></label>
          <label><span>HP maximum</span><input type="number" min="1" value={selectedEnemy.hp.max} onChange={(event) => updateEnemy({ ...selectedEnemy, hp: { ...selectedEnemy.hp, max: Number(event.target.value) } })} /></label>
        </div></section>
        <section className="panel fields"><div className="panel-title"><div><h2>Room generation</h2><p>These settings control where this enemy can appear. Power is calculated from its average damage and HP.</p></div></div><div className="field-grid">
          <label className="check"><input type="checkbox" checked={selectedEnemy.enabled} onChange={(event) => updateEnemy({ ...selectedEnemy, enabled: event.target.checked })} /> Enemy enabled</label>
          <label className="check"><input type="checkbox" checked={selectedEnemy.generation.spawnEnabled} onChange={(event) => updateEnemy({ ...selectedEnemy, generation: { ...selectedEnemy.generation, spawnEnabled: event.target.checked } })} /> Include in random rooms</label>
          <label className="check"><input type="checkbox" checked={selectedEnemy.generation.bossOnly} onChange={(event) => updateEnemy({ ...selectedEnemy, generation: { ...selectedEnemy.generation, bossOnly: event.target.checked } })} /> Boss only</label>
          <label><span>Spawn weight</span><input type="number" min="0.01" step="0.1" value={selectedEnemy.generation.spawnWeight} onChange={(event) => updateEnemy({ ...selectedEnemy, generation: { ...selectedEnemy.generation, spawnWeight: Number(event.target.value) } })} /></label>
          <label><span>Maximum copies per encounter</span><input type="number" min="1" max="4" value={selectedEnemy.generation.maximumCopies} onChange={(event) => updateEnemy({ ...selectedEnemy, generation: { ...selectedEnemy.generation, maximumCopies: Number(event.target.value) } })} /></label>
          <label><span>Minimum room</span><input type="number" min="1" value={selectedEnemy.generation.minimumRoom} onChange={(event) => updateEnemy({ ...selectedEnemy, generation: { ...selectedEnemy.generation, minimumRoom: Number(event.target.value) } })} /></label>
          <label><span>Maximum room (optional)</span><input type="number" min={selectedEnemy.generation.minimumRoom} value={selectedEnemy.generation.maximumRoom ?? ""} placeholder="No maximum" onChange={(event) => updateEnemy({ ...selectedEnemy, generation: { ...selectedEnemy.generation, maximumRoom: event.target.value === "" ? undefined : Number(event.target.value) } })} /></label>
          <label><span>Power override (optional)</span><input type="number" min="0.01" step="0.01" value={selectedEnemy.generation.powerOverride ?? ""} placeholder={enemyPower({ ...selectedEnemy, generation: { ...selectedEnemy.generation, powerOverride: undefined } }).toFixed(2)} onChange={(event) => updateEnemy({ ...selectedEnemy, generation: { ...selectedEnemy.generation, powerOverride: event.target.value === "" ? undefined : Number(event.target.value) } })} /></label>
          <label><span>Tags (comma separated)</span><input value={selectedEnemy.generation.tags.join(", ")} placeholder="undead, tank" onChange={(event) => updateEnemy({ ...selectedEnemy, generation: { ...selectedEnemy.generation, tags: event.target.value.split(",").map((tag) => tag.trim().toLowerCase()).filter(Boolean) } })} /></label>
        </div></section>
        <section className="enemy-preview"><div className="enemy-sprite">{selectedEnemy.name.slice(0, 1).toUpperCase() || "?"}</div><div><b>{selectedEnemy.name || "Untitled enemy"}</b><span>HP {selectedEnemy.hp.min}–{selectedEnemy.hp.max}</span><span>ATK {selectedEnemy.damage.min}–{selectedEnemy.damage.max}</span><span>POWER {enemyPower(selectedEnemy).toFixed(2)}</span></div></section>
      </>}
      {selectedRoom && <>
        <div className="section-heading"><div><span>Encounter curve</span><h1>Room {selectedRoom.room}</h1></div><div className="power-chip">POWER {selectedRoom.power}</div></div>
        <section className="panel fields"><div className="panel-title"><div><h2>Generation budget</h2><p>The runtime builds eligible enemy groups and chooses one inside this power window.</p></div></div><div className="field-grid">
          <label><span>Target power</span><input type="number" min="0.01" step="0.1" value={selectedRoom.power} onChange={(event) => updateRoom({ ...selectedRoom, power: Number(event.target.value) })} /></label>
          <label><span>Accepted power window</span><input className="derived-id" readOnly value={`${(selectedRoom.power * selectedRoom.minimumBudgetRatio).toFixed(2)} – ${(selectedRoom.power * selectedRoom.maximumBudgetRatio).toFixed(2)}`} /></label>
          <label><span>Minimum enemies</span><input type="number" min="1" max="4" value={selectedRoom.minimumEnemies} onChange={(event) => updateRoom({ ...selectedRoom, minimumEnemies: Number(event.target.value) })} /></label>
          <label><span>Maximum enemies</span><input type="number" min="1" max="4" value={selectedRoom.maximumEnemies} onChange={(event) => updateRoom({ ...selectedRoom, maximumEnemies: Number(event.target.value) })} /></label>
          <label><span>Minimum budget ratio</span><input type="number" min="0.01" step="0.01" value={selectedRoom.minimumBudgetRatio} onChange={(event) => updateRoom({ ...selectedRoom, minimumBudgetRatio: Number(event.target.value) })} /></label>
          <label><span>Maximum budget ratio</span><input type="number" min="0.01" step="0.01" value={selectedRoom.maximumBudgetRatio} onChange={(event) => updateRoom({ ...selectedRoom, maximumBudgetRatio: Number(event.target.value) })} /></label>
          <label><span>Required tags</span><input value={selectedRoom.requiredTags.join(", ")} placeholder="Optional" onChange={(event) => updateRoom({ ...selectedRoom, requiredTags: event.target.value.split(",").map((tag) => tag.trim().toLowerCase()).filter(Boolean) })} /></label>
          <label><span>Excluded tags</span><input value={selectedRoom.excludedTags.join(", ")} placeholder="Optional" onChange={(event) => updateRoom({ ...selectedRoom, excludedTags: event.target.value.split(",").map((tag) => tag.trim().toLowerCase()).filter(Boolean) })} /></label>
        </div></section>
        <section className="panel"><div className="panel-title"><div><h2>Matching encounters</h2><p>{selectedRoomCandidates.length} composition{selectedRoomCandidates.length === 1 ? "" : "s"} currently fit the accepted power window.</p></div></div><div className="candidate-list">{selectedRoomCandidates.slice(0, 12).map((candidate) => <div key={candidate.enemyIds.join("|")}><span>{candidate.enemyIds.map((id) => content.enemies.find((enemy) => enemy.id === id)?.name || id).join(" + ")}</span><b>{candidate.power.toFixed(2)}</b></div>)}{selectedRoomCandidates.length === 0 && <em>No matching encounter. Adjust the budget, tolerance, or enemy eligibility.</em>}</div></section>
      </>}
      {selectedEndless && <>
        <div className="section-heading"><div><span>Full-deck benchmark</span><h1>Endless mode</h1></div><div className="card-chip endless">NO SHOP</div></div>
        <section className="panel fields"><div className="panel-title"><div><h2>Scaling curve</h2><p>After the Bone Lord, the completed deck continues through increasingly scaled encounters without card rewards.</p></div></div><div className="field-grid">
          <label><span>Starting power</span><input type="number" min="0.01" step="0.1" value={selectedEndless.startingPower} onChange={(event) => updateEndless({ ...selectedEndless, startingPower: Number(event.target.value) })} /></label>
          <label><span>Power gained per room</span><input type="number" min="0.01" step="0.1" value={selectedEndless.powerPerRoom} onChange={(event) => updateEndless({ ...selectedEndless, powerPerRoom: Number(event.target.value) })} /></label>
          <label><span>Minimum enemies</span><input type="number" min="1" max="4" value={selectedEndless.minimumEnemies} onChange={(event) => updateEndless({ ...selectedEndless, minimumEnemies: Number(event.target.value) })} /></label>
          <label><span>Maximum enemies</span><input type="number" min="1" max="4" value={selectedEndless.maximumEnemies} onChange={(event) => updateEndless({ ...selectedEndless, maximumEnemies: Number(event.target.value) })} /></label>
          <label><span>Minimum budget ratio</span><input type="number" min="0.01" step="0.01" value={selectedEndless.minimumBudgetRatio} onChange={(event) => updateEndless({ ...selectedEndless, minimumBudgetRatio: Number(event.target.value) })} /></label>
          <label><span>Maximum budget ratio</span><input type="number" min="0.01" step="0.01" value={selectedEndless.maximumBudgetRatio} onChange={(event) => updateEndless({ ...selectedEndless, maximumBudgetRatio: Number(event.target.value) })} /></label>
        </div></section>
      </>}
      {selection.kind === "world" && <RoomBuilder mode={selection.id} />}
    </main>
    <aside className="preview"><div className="preview-heading"><div><span>Live preview</span><b>{status}</b></div><span className={`live-dot ${previewRunning ? "" : "stopped"}`} /></div>{selectedCard && <div className={`card-preview element-${selectedCard.element}`}><div className="mana-orb">{selectedCard.cost}</div><small>{selectedCard.type} · {selectedCard.element}</small><h2>{selectedCard.name}</h2><div className="art-placeholder"><span>✦</span></div><p>{describeCard(selectedCard) || "Add an effect to generate rules text."}</p></div>}<div className="game-frame"><div className="game-frame-title"><span>{previewRunning ? "Running game" : "Game preview stopped"}</span><div className="game-frame-actions"><button type="button" disabled={previewRunning} onClick={() => loadPreview("Starting preview…")}>Start</button><button type="button" disabled={!previewRunning} onClick={stopPreview}>Stop</button></div></div>{previewRunning ? <iframe key={previewInstance} ref={iframeRef} title="Pixel Card Game preview" src={`${gameUrl}?revision=${encodeURIComponent(content.contentRevision)}&instance=${previewInstance}`} /> : <div className="game-frame-idle"><b>Preview is off</b><span>Start it when you are ready to test the current draft.</span></div>}</div>{issues.length > 0 && <div className="issues"><h3>Needs attention</h3>{issues.slice(0, 6).map((issue) => <p key={`${issue.path}-${issue.message}`}><b>{issue.path}</b>{issue.message}</p>)}</div>}</aside>
  </div></AuthoringCards.Provider>;
}
