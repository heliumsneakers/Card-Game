import type { CardDefinition, ContentDocument, Effect, EndlessDefinition, EnemyDefinition, Expression, RoomDefinition } from "./model";

export interface Issue { path: string; message: string }

const elements = new Set(["fire", "ice", "nature", "earth", "arcane"]);

function defaultElement(type: CardDefinition["type"]): CardDefinition["element"] {
  if (type === "HEAL") return "nature";
  if (type === "DEF") return "earth";
  if (type === "UTIL") return "arcane";
  return "fire";
}

export function contentId(kind: "card" | "enemy", name: string): string {
  const slug = name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return `${kind}.${slug || "untitled"}`;
}

export const defaultRoomCurve: RoomDefinition[] = [
  { room: 1, power: 1, minimumEnemies: 1, maximumEnemies: 2, minimumBudgetRatio: 0.9, maximumBudgetRatio: 1.05, requiredTags: [], excludedTags: [] },
  { room: 2, power: 3, minimumEnemies: 1, maximumEnemies: 3, minimumBudgetRatio: 0.9, maximumBudgetRatio: 1.05, requiredTags: [], excludedTags: [] },
  { room: 3, power: 5, minimumEnemies: 1, maximumEnemies: 4, minimumBudgetRatio: 0.9, maximumBudgetRatio: 1.05, requiredTags: [], excludedTags: [] },
  { room: 4, power: 7, minimumEnemies: 1, maximumEnemies: 4, minimumBudgetRatio: 0.9, maximumBudgetRatio: 1.05, requiredTags: [], excludedTags: [] },
];

export const defaultEndless: EndlessDefinition = {
  startingPower: 9,
  powerPerRoom: 2,
  minimumEnemies: 1,
  maximumEnemies: 4,
  minimumBudgetRatio: 0.9,
  maximumBudgetRatio: 1.05,
};

export function enemyPower(enemy: EnemyDefinition): number {
  if (enemy.generation?.powerOverride !== undefined) return enemy.generation.powerOverride;
  const averageHp = (enemy.hp.min + enemy.hp.max) / 2;
  const averageDamage = (enemy.damage.min + enemy.damage.max) / 2;
  return (averageHp / 8.5) * (0.4 + 0.6 * (averageDamage / 2.5));
}

export function groupMultiplier(count: number): number {
  if (count <= 1) return 1;
  if (count === 2) return 1.5;
  if (count === 3) return 1.8;
  return 2;
}

export interface EncounterCandidate { enemyIds: string[]; power: number }

export function encounterCandidates(content: ContentDocument, room: RoomDefinition): EncounterCandidate[] {
  const eligible = content.enemies
    .filter((enemy) => enemy.enabled && enemy.generation.spawnEnabled && !enemy.generation.bossOnly)
    .filter((enemy) => room.room >= enemy.generation.minimumRoom && (enemy.generation.maximumRoom === undefined || room.room <= enemy.generation.maximumRoom))
    .sort((a, b) => a.id.localeCompare(b.id));
  const results: EncounterCandidate[] = [];
  const current: EnemyDefinition[] = [];
  const counts = new Map<string, number>();
  const hasTag = (enemy: EnemyDefinition, tag: string) => enemy.generation.tags.includes(tag);
  const visit = (startIndex: number, targetCount: number) => {
    if (current.length === targetCount) {
      if (room.excludedTags.some((tag) => current.some((enemy) => hasTag(enemy, tag)))) return;
      if (room.requiredTags.some((tag) => !current.some((enemy) => hasTag(enemy, tag)))) return;
      results.push({
        enemyIds: current.map((enemy) => enemy.id),
        power: current.reduce((sum, enemy) => sum + enemyPower(enemy), 0) * groupMultiplier(current.length),
      });
      return;
    }
    for (let index = startIndex; index < eligible.length; index += 1) {
      const enemy = eligible[index];
      const count = counts.get(enemy.id) || 0;
      if (count >= enemy.generation.maximumCopies) continue;
      current.push(enemy);
      counts.set(enemy.id, count + 1);
      visit(index, targetCount);
      counts.set(enemy.id, count);
      current.pop();
    }
  };
  for (let count = room.minimumEnemies; count <= room.maximumEnemies; count += 1) visit(0, count);
  return results.sort((a, b) => a.power - b.power);
}

function defaultGeneration(enemy: Pick<EnemyDefinition, "id">): EnemyDefinition["generation"] {
  return {
    spawnEnabled: enemy.id !== "enemy.bone_lord",
    spawnWeight: 1,
    minimumRoom: 1,
    maximumCopies: 4,
    bossOnly: enemy.id === "enemy.bone_lord",
    tags: enemy.id === "enemy.bone_lord" ? ["boss", "undead"] : [],
  };
}

function expressionText(expression: Expression): string {
  if (expression.kind === "literal") return String(expression.value);
  if (expression.kind === "counter") return "times this card was played this turn";
  if (expression.kind === "local") return expression.name;
  if (expression.kind === "context") {
    const labels: Record<string, string> = { previousCardId: "the previous card", thisCardId: "this card", mana: "current mana", hp: "current HP", turn: "the turn", livingEnemies: "living enemies" };
    return labels[expression.path];
  }
  const symbols: Record<string, string> = { add: "+", subtract: "−", multiply: "×", min: "minimum of", max: "maximum of", eq: "is", ne: "is not", lt: "is less than", lte: "is at most", gt: "is greater than", gte: "is at least" };
  return `${expressionText(expression.left)} ${symbols[expression.operator]} ${expressionText(expression.right)}`;
}

function effectText(effect: Effect): string {
  if (effect.op === "damage") return `Deal ${expressionText(effect.amount)} damage${effect.target === "allEnemies" ? " to all enemies" : ""}.`;
  if (effect.op === "freeze") return effect.target === "allEnemies" ? "Freeze them." : "Freeze the target.";
  if (effect.op === "armor") return `Gain ${expressionText(effect.amount)} Armor.`;
  if (effect.op === "heal") return `Heal ${expressionText(effect.amount)} HP.`;
  if (effect.op === "draw") return `Draw ${expressionText(effect.amount)} cards.`;
  if (effect.op === "mana") return `Gain ${expressionText(effect.amount)} mana this turn.`;
  if (effect.op === "addStatus") return effect.id === "status.mirror" ? "Copy your next spell. Its copy costs 1 less." : "Spell power ×2. Stacks.";
  if (effect.op === "if") return `If ${expressionText(effect.condition)}, ${effect.then.map(effectText).join(" ").replace(/^./, (character) => character.toLowerCase())}`;
  return "";
}

const descriptionToken = /\{([a-z][a-z0-9_]*)\s*=\s*([^{}]+)\}/gi;

function evaluateDisplayFormula(source: string): number | undefined {
  const compact = source.replace(/\s+/g, "");
  if (!/^\d+(?:[+*-]\d+)*$/.test(compact)) return undefined;
  const terms = compact.split(/([+-])/);
  const multiply = (term: string) => term.split("*").reduce((total, value) => total * Number(value), 1);
  let value = multiply(terms[0]);
  for (let index = 1; index < terms.length; index += 2) {
    const next = multiply(terms[index + 1]);
    value = terms[index] === "+" ? value + next : value - next;
  }
  return Math.max(0, Math.floor(value));
}

function flattenedEffects(effects: Effect[]): Effect[] {
  return effects.flatMap((effect) => effect.op === "if"
    ? [effect, ...flattenedEffects(effect.then), ...flattenedEffects(effect.else || [])]
    : [effect]);
}

function staticEffectValue(expression: Expression, effects: Effect[], seen = new Set<string>()): number | undefined {
  if (expression.kind === "literal") return expression.value;
  if (expression.kind === "counter" || expression.kind === "context") return 0;
  if (expression.kind === "compare") return undefined;
  if (expression.kind === "local") {
    if (seen.has(expression.name)) return undefined;
    const setter = flattenedEffects(effects).find((effect): effect is Extract<Effect, { op: "setLocal" }> => effect.op === "setLocal" && effect.name === expression.name);
    if (!setter) return undefined;
    seen.add(expression.name);
    return staticEffectValue(setter.value, effects, seen);
  }
  const left = staticEffectValue(expression.left, effects, seen);
  const right = staticEffectValue(expression.right, effects, seen);
  if (left === undefined || right === undefined) return undefined;
  if (expression.operator === "add") return left + right;
  if (expression.operator === "subtract") return left - right;
  if (expression.operator === "multiply") return left * right;
  if (expression.operator === "min") return Math.min(left, right);
  return Math.max(left, right);
}

const tokenEffectOps: Record<string, Effect["op"]> = { dmg: "damage", armor: "armor", heal: "heal", draw: "draw", mana: "mana", stacks: "addStatus" };

export function renderDescription(template: string, effects: Effect[] = []): string {
  const allEffects = flattenedEffects(effects);
  const occurrences: Record<string, number> = {};
  return template.replace(descriptionToken, (_token, name: string, formula: string) => {
    const value = evaluateDisplayFormula(formula);
    if (value === undefined) return "?";
    const baseName = name.replace(/\d+$/, "");
    occurrences[baseName] = (occurrences[baseName] || 0) + 1;
    const matching = allEffects.filter((effect) => effect.op === tokenEffectOps[baseName]);
    const effect = matching[(Number(name.match(/\d+$/)?.[0]) || occurrences[baseName]) - 1];
    let resolved: number | undefined;
    if (effect?.op === "addStatus") resolved = staticEffectValue(effect.stacks, effects);
    else if (effect && (effect.op === "damage" || effect.op === "armor" || effect.op === "heal" || effect.op === "draw" || effect.op === "mana")) resolved = staticEffectValue(effect.amount, effects);
    const displayed = resolved ?? value;
    const modified = /[+*-]/.test(formula.trim().slice(1)) || (resolved !== undefined && resolved !== value);
    return `${displayed}${modified ? "*" : ""}`;
  });
}

export function describeCard(card: CardDefinition): string {
  const template = card.description || card.effects.map(effectText).filter(Boolean).join(" ");
  return renderDescription(template, card.effects);
}

function migratedDescription(card: CardDefinition): string {
  const counters: Record<string, number> = {};
  const token = (name: string, expression: Expression) => {
    counters[name] = (counters[name] || 0) + 1;
    const numberedName = counters[name] === 1 ? name : `${name}${counters[name]}`;
    return `{${numberedName}=${staticEffectValue(expression, card.effects) ?? 0}}`;
  };
  return card.effects.map((effect) => {
    if (effect.op === "damage") return `Deal ${token("dmg", effect.amount)} damage${effect.target === "allEnemies" ? " to all enemies" : " to target"}.`;
    if (effect.op === "freeze") return effect.target === "allEnemies" ? "Freeze them." : "Freeze the target.";
    if (effect.op === "armor") return `Gain ${token("armor", effect.amount)} Armor.`;
    if (effect.op === "heal") return `Heal ${token("heal", effect.amount)} HP.`;
    if (effect.op === "draw") return `Draw ${token("draw", effect.amount)} cards.`;
    if (effect.op === "mana") return `Gain ${token("mana", effect.amount)} mana this turn.`;
    if (effect.op === "addStatus") return effect.id === "status.mirror" ? "Copy your next spell. Its copy costs 1 less." : "Spell power ×2. Stacks.";
    if (effect.op === "if") return effectText(effect);
    return "";
  }).filter(Boolean).join(" ");
}

export function migrateDescriptions(content: ContentDocument): ContentDocument {
  return {
    ...content,
    cards: content.cards.map((card) => ({
      ...card,
      element: card.element || defaultElement(card.type),
      description: card.description === undefined ? migratedDescription(card) : card.description,
    })),
    enemies: content.enemies.map((enemy) => ({
      ...enemy,
      generation: {
        ...defaultGeneration(enemy),
        ...(enemy.generation || {}),
        tags: enemy.generation?.tags || (enemy as unknown as { tags?: string[] }).tags || defaultGeneration(enemy).tags,
      },
    })),
    roomCurve: (content.roomCurve || defaultRoomCurve).map((room) => ({
      ...room,
      requiredTags: room.requiredTags || [],
      excludedTags: room.excludedTags || [],
    })),
    endless: { ...defaultEndless, ...(content.endless || {}) },
  };
}

export function validateContent(content: ContentDocument): Issue[] {
  const issues: Issue[] = [];
  const ids = new Set<string>();
  const add = (path: string, message: string) => issues.push({ path, message });
  content.cards.forEach((card, index) => {
    const path = `cards[${index}]`;
    if (!/^card\.[a-z0-9_]+$/.test(card.id)) add(`${path}.id`, "Use an ID such as card.fireball.");
    if (card.id !== contentId("card", card.name)) add(`${path}.id`, "Stable ID must match the card name.");
    if (ids.has(card.id)) add(`${path}.id`, "This ID is already in use.");
    ids.add(card.id);
    if (!card.name.trim()) add(`${path}.name`, "Card name is required.");
    if (!Number.isInteger(card.cost) || card.cost < 0) add(`${path}.cost`, "Mana cost must be a non-negative whole number.");
    if (!elements.has(card.element)) add(`${path}.element`, "Choose Fire, Ice, Nature, Earth, or Arcane.");
    if (!card.description?.trim()) add(`${path}.description`, "Write a card description.");
    if ((card.description?.length || 0) > 500) add(`${path}.description`, "Description cannot exceed 500 characters.");
    const strippedDescription = (card.description || "").replace(descriptionToken, "");
    if (/[{}]/.test(strippedDescription)) add(`${path}.description`, "Value blocks must look like {dmg=2}.");
    for (const match of (card.description || "").matchAll(descriptionToken)) {
      if (evaluateDisplayFormula(match[2]) === undefined) add(`${path}.description`, `Invalid formula in {${match[1]}=…}. Use whole numbers with +, - or *.`);
    }
    if (!card.effects.length) add(`${path}.effects`, "Add at least one effect.");
    card.effects.forEach((effect, effectIndex) => {
      if ((effect.op === "damage" || effect.op === "freeze") && effect.target === "selectedEnemy" && card.target !== "enemy") {
        add(`${path}.effects[${effectIndex}].target`, "Selected Enemy requires the card target One Enemy.");
      }
      if ((effect.op === "damage" || effect.op === "freeze") && effect.target === "allEnemies" && card.target !== "all") {
        add(`${path}.effects[${effectIndex}].target`, "All Enemies requires the card target All Enemies.");
      }
    });
  });
  content.enemies.forEach((enemy, index) => {
    const path = `enemies[${index}]`;
    if (!/^enemy\.[a-z0-9_]+$/.test(enemy.id)) add(`${path}.id`, "Use an ID such as enemy.goblin.");
    if (enemy.id !== contentId("enemy", enemy.name)) add(`${path}.id`, "Stable ID must match the enemy name.");
    if (ids.has(enemy.id)) add(`${path}.id`, "This ID is already in use.");
    ids.add(enemy.id);
    if (!enemy.name.trim()) add(`${path}.name`, "Enemy name is required.");
    if (enemy.damage.min < 0 || enemy.damage.min > enemy.damage.max) add(`${path}.damage`, "Damage minimum must be at least zero and no greater than maximum.");
    if (enemy.hp.min < 1 || enemy.hp.min > enemy.hp.max) add(`${path}.hp`, "HP minimum must be at least one and no greater than maximum.");
    const generation = enemy.generation;
    if (!generation) add(`${path}.generation`, "Generation settings are required.");
    else {
      if (!Number.isFinite(generation.spawnWeight) || generation.spawnWeight <= 0) add(`${path}.generation.spawnWeight`, "Spawn weight must be greater than zero.");
      if (!Number.isInteger(generation.minimumRoom) || generation.minimumRoom < 1) add(`${path}.generation.minimumRoom`, "Minimum room must be a positive whole number.");
      if (generation.maximumRoom !== undefined && (!Number.isInteger(generation.maximumRoom) || generation.maximumRoom < generation.minimumRoom)) add(`${path}.generation.maximumRoom`, "Maximum room must be at least the minimum room.");
      if (!Number.isInteger(generation.maximumCopies) || generation.maximumCopies < 1 || generation.maximumCopies > 4) add(`${path}.generation.maximumCopies`, "Maximum copies must be from 1 to 4.");
      if (generation.powerOverride !== undefined && (!Number.isFinite(generation.powerOverride) || generation.powerOverride <= 0)) add(`${path}.generation.powerOverride`, "Power override must be greater than zero.");
      if (generation.tags.some((tag) => !/^[a-z0-9_]+$/.test(tag))) add(`${path}.generation.tags`, "Tags use lowercase letters, numbers, and underscores.");
    }
  });
  const roomNumbers = new Set<number>();
  content.roomCurve.forEach((room, index) => {
    const path = `roomCurve[${index}]`;
    if (!Number.isInteger(room.room) || room.room < 1 || room.room > 4) add(`${path}.room`, "Normal room number must be from 1 to 4.");
    if (roomNumbers.has(room.room)) add(`${path}.room`, "Room number must be unique.");
    roomNumbers.add(room.room);
    validateEncounterSettings(room, path, add);
    if ([...room.requiredTags, ...room.excludedTags].some((tag) => !/^[a-z0-9_]+$/.test(tag))) add(path, "Room tags use lowercase letters, numbers, and underscores.");
    const safeCounts = Number.isInteger(room.minimumEnemies) && Number.isInteger(room.maximumEnemies)
      && room.minimumEnemies >= 1 && room.maximumEnemies >= room.minimumEnemies && room.maximumEnemies <= 4;
    const lower = room.power * room.minimumBudgetRatio;
    const upper = room.power * room.maximumBudgetRatio;
    if (safeCounts && Number.isFinite(lower) && Number.isFinite(upper)
      && !encounterCandidates(content, room).some((candidate) => candidate.power >= lower && candidate.power <= upper)) {
      add(path, "No eligible enemy combination falls inside this room's power window.");
    }
  });
  for (let room = 1; room <= 4; room += 1) if (!roomNumbers.has(room)) add("roomCurve", `Room ${room} needs generation settings.`);
  validateEncounterSettings(content.endless, "endless", add);
  if (!Number.isFinite(content.endless.startingPower) || content.endless.startingPower <= 0) add("endless.startingPower", "Starting power must be greater than zero.");
  if (!Number.isFinite(content.endless.powerPerRoom) || content.endless.powerPerRoom <= 0) add("endless.powerPerRoom", "Power gained per room must be greater than zero.");
  return issues;
}

function validateEncounterSettings(
  settings: Pick<RoomDefinition, "power" | "minimumEnemies" | "maximumEnemies" | "minimumBudgetRatio" | "maximumBudgetRatio"> | EndlessDefinition,
  path: string,
  add: (path: string, message: string) => void,
) {
  if ("power" in settings && (!Number.isFinite(settings.power) || settings.power <= 0)) add(`${path}.power`, "Power must be greater than zero.");
  if (!Number.isInteger(settings.minimumEnemies) || settings.minimumEnemies < 1 || settings.minimumEnemies > 4) add(`${path}.minimumEnemies`, "Minimum enemies must be from 1 to 4.");
  if (!Number.isInteger(settings.maximumEnemies) || settings.maximumEnemies < settings.minimumEnemies || settings.maximumEnemies > 4) add(`${path}.maximumEnemies`, "Maximum enemies must be at least the minimum and no greater than 4.");
  if (!Number.isFinite(settings.minimumBudgetRatio) || settings.minimumBudgetRatio <= 0) add(`${path}.minimumBudgetRatio`, "Minimum budget ratio must be greater than zero.");
  if (!Number.isFinite(settings.maximumBudgetRatio) || settings.maximumBudgetRatio < settings.minimumBudgetRatio) add(`${path}.maximumBudgetRatio`, "Maximum budget ratio must be at least the minimum.");
}

export function deterministicJson(content: ContentDocument): string {
  return `${JSON.stringify(content, null, 2)}\n`;
}

export function removeCard(content: ContentDocument, cardId: string): ContentDocument {
  return {
    ...content,
    contentRevision: `draft-${Date.now()}`,
    cards: content.cards.filter((card) => card.id !== cardId),
  };
}
