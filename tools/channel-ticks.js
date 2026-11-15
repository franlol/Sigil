// Builds Sigil's ChannelTicks.lua from the game's spell tables (wago.tools CSV).
// usage: node tools/channel-ticks.js <csv folder> <build> ChannelTicks.lua
// The CSVs (SpellMisc, SpellEffect, SpellName, SpellDuration, SkillLineAbility,
// ItemEffect) come from https://wago.tools/db2/<Table>/csv?build=<build>
// A spell is kept when it is channeled, has a periodic effect and ticks 2+ times,
// and players can get it: learned (SkillLineAbility), used from an item (ItemEffect),
// or named like one of those (the channel such a spell starts).
const fs = require("fs");
const path = require("path");
const [dir, build, out] = process.argv.slice(2);

function parse(name) {
  const text = fs.readFileSync(path.join(dir, name + ".csv"), "utf8");
  const rows = [];
  let row = [], field = "", q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else q = false; }
      else field += c;
    } else if (c === '"') q = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n") { row.push(field.replace(/\r$/, "")); rows.push(row); row = []; field = ""; }
    else field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  const head = rows.shift();
  return rows.filter(r => r.length === head.length).map(r => Object.fromEntries(head.map((h, i) => [h, r[i]])));
}

const misc = parse("SpellMisc"), eff = parse("SpellEffect"), names = parse("SpellName");
const dur = new Map(parse("SpellDuration").map(r => [r.ID, +r.Duration]));
const nameOf = new Map(names.map(r => [r.ID, r.Name_lang]));
const usable = new Set(parse("SkillLineAbility").map(r => r.Spell));
for (const r of parse("ItemEffect")) usable.add(r.SpellID);

// shortest periodic effect of each spell (ms)
const period = new Map();
for (const e of eff) {
  const p = +e.EffectAuraPeriod;
  if (p > 0 && (!period.has(e.SpellID) || p < period.get(e.SpellID))) period.set(e.SpellID, p);
}

const channels = misc.filter(m => (+m.Attributes_1 & 0x4) || (+m.Attributes_1 & 0x40));
const ticks = new Map();      // spellID -> count
const byName = new Map();     // name -> count, for channels whose ticks live on another spell
for (const m of channels) {
  const p = period.get(m.SpellID), d = dur.get(m.DurationIndex);
  if (!p || !(d > 0)) continue;
  const n = Math.round(d / p);
  if (n < 2) continue;
  ticks.set(m.SpellID, n);
  byName.set(nameOf.get(m.SpellID), n);
}
// a channel with no ticks of its own (e.g. Penance: a dummy that starts the real
// channel) takes the count of the channel with the same name
for (const m of channels) {
  if (ticks.has(m.SpellID) || period.has(m.SpellID)) continue;
  const n = byName.get(nameOf.get(m.SpellID));
  if (n) ticks.set(m.SpellID, n);
}

// also the channel a learned spell starts under the same name (Cannibalize, Penance)
const usableNames = new Set([...usable].map(id => nameOf.get(id)).filter(Boolean));
const keep = [...ticks.keys()].filter(id => usable.has(id) || usableNames.has(nameOf.get(id))).map(Number).sort((a, b) => a - b);
const lines = keep.map(id => `    [${id}] = ${ticks.get(String(id))},   -- ${nameOf.get(String(id))}`);
const lua = `-------------------------------------------------------------------------------
-- Sigil - Channel ticks: how many times each channeled spell ticks.
-- The game does not tell addons; this list is built from its own spell data
-- (build ${build}) by a script: [spell ID] = ticks over the full channel.
-------------------------------------------------------------------------------

local _, ns = ...

ns.CHANNEL_TICKS = {
${lines.join("\n")}
}
`;
if (out) fs.writeFileSync(out, lua.replace(/\n/g, "\r\n"));
console.log(keep.length + " spells");
console.log(keep.map(id => nameOf.get(String(id))).filter((v, i, a) => a.indexOf(v) === i).join(", "));
