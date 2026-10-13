/* Shared sample data, game-window helpers and the state switcher. Sample data only. */
"use strict";

const ICONS = {
  "inv_belt_13": "@@icon-inv_belt_13.png@@",
  "inv_boots_07": "@@icon-inv_boots_07.png@@",
  "inv_bracer_03": "@@icon-inv_bracer_03.png@@",
  "inv_chest_cloth_18": "@@icon-inv_chest_cloth_18.png@@",
  "inv_gauntlets_13": "@@icon-inv_gauntlets_13.png@@",
  "inv_helmet_08": "@@icon-inv_helmet_08.png@@",
  "inv_jewelry_necklace_07": "@@icon-inv_jewelry_necklace_07.png@@",
  "inv_jewelry_ring_05": "@@icon-inv_jewelry_ring_05.png@@",
  "inv_misc_bag_10": "@@icon-inv_misc_bag_10.png@@",
  "inv_misc_book_09": "@@icon-inv_misc_book_09.png@@",
  "spell_fire_fire": "@@icon-spell_fire_fire.png@@",
};
const ICON = (n) => ICONS[n];
const ASSET = {
  de: "@@de.png@@", dice: "@@dice.png@@", alert: "@@alert.png@@", check: "@@check.png@@", checkUp: "@@check-up.png@@",
  dotGreen: "@@dot-green.png@@", dotRed: "@@dot-red.png@@", dotYellow: "@@dot-yellow.png@@", dotGray: "@@dot-gray.png@@",
};

/* ---------- Sample data ---------- */
const PEOPLE = {
  "Konvett Konvett": "warrior", "Seraphine Ashdown": "priest", "Ashla Brightwater": "mage", "Doran Vale": "warlock",
  "Mirel Stone": "priest", "Tovin Hale": "mage", "Kessa Moorfield": "druid", "Bram Ironvein": "warrior",
  "Lyra Dawnmere": "mage", "Ostrin Pike": "paladin", "Celwen Thorne": "druid", "Garrick Fenn": "hunter",
  "Ysolde Marr": "warlock", "Pell Harrow": "warrior", "Quill Ashby": "rogue", "Rhona Teague": "priest",
  "Silas Crane": "rogue", "Vena Holt": "hunter", "Wren Calder": "shaman", "Edric Moss": "mage", "Fenna Lark": "priest",
  "Hollis Grey": "paladin", "Ardan Vey": "warrior", "Bellis Rook": "rogue", "Corwin Slate": "hunter",
};
const ITEMS = {
  choker: { name: "Choker of Enlightenment", q: "epic", icon: "inv_jewelry_necklace_07", slot: "Neck", stats: ["+10 Intellect", "+9 Spirit", "Equip: Increases damage and healing done by magical spells and effects by up to 18."] },
  gloves: { name: "Felheart Gloves", q: "epic", icon: "inv_gauntlets_13", slot: "Hands · Cloth", stats: ["50 Armor", "+18 Stamina", "+13 Intellect", "Warlock"] },
  gauntlets: { name: "Gauntlets of Might", q: "epic", icon: "inv_gauntlets_13", slot: "Hands · Plate", stats: ["615 Armor", "+22 Strength", "+17 Stamina"] },
  robe: { name: "Robe of Volatile Power", q: "epic", icon: "inv_chest_cloth_18", slot: "Chest · Cloth", stats: ["89 Armor", "+10 Stamina", "+15 Intellect", "Equip: Improves your chance to get a critical strike with spells by 2%."] },
  ring: { name: "Ring of Spell Power", q: "epic", icon: "inv_jewelry_ring_05", slot: "Finger", stats: ["Equip: Increases damage and healing done by magical spells and effects by up to 33."] },
  wrist: { name: "Wristguards of Stability", q: "epic", icon: "inv_bracer_03", slot: "Wrist · Leather", stats: ["63 Armor", "+24 Strength", "+8 Stamina"] },
  core: { name: "Fiery Core", q: "rare", icon: "spell_fire_fire", slot: "Trade goods", stats: [] },
  belt: { name: "Belt of Might", q: "epic", icon: "inv_belt_13", slot: "Waist · Plate", stats: ["484 Armor", "+21 Stamina", "+7 Strength"] },
  helm: { name: "Circlet of Prophecy", q: "epic", icon: "inv_helmet_08", slot: "Head · Cloth", stats: ["80 Armor", "+27 Intellect", "+20 Spirit"] },
  boots: { name: "Felheart Slippers", q: "epic", icon: "inv_boots_07", slot: "Feet · Cloth", stats: ["57 Armor", "+18 Stamina", "+11 Intellect"] },
};
const RAID = "Molten Core, Thu 10 Dec";
const LM = "Konvett Konvett";
const STATUS_LINE = "Reserves: " + RAID + " · copied 19:42, loaded 19:50";
const CODE = (k) => "{bf:A7K2-" + k + "}";

/* ---------- Small HTML helpers ---------- */
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
function who(name, opts = {}) {
  const cls = PEOPLE[name] ? "c-" + PEOPLE[name] : "";
  return `<span class="${cls} ${opts.absent ? "absent" : ""} ${opts.struck ? "struck" : ""}">${esc(name)}</span>`;
}
function link(key, br = true) { const it = ITEMS[key]; return `<span class="q-${it.q}">${br ? "[" : ""}${esc(it.name)}${br ? "]" : ""}</span>`; }
function icon(key, size = "") { const it = ITEMS[key]; return `<span class="icon ${size} border-${it.q}" style="background-image:url(${ICON(it.icon)})" role="img" aria-label="${esc(it.name)}"></span>`; }
function btn(label, o = {}) {
  const attrs = [o.goto ? `data-goto="${o.goto}"` : "", o.disabled ? "disabled" : "", o.title ? `title="${esc(o.title)}"` : "", o.focus !== undefined ? `data-focus="${o.focus}"` : ""].join(" ");
  const ico = o.ico ? `<img class="ico" alt="" src="${o.ico}">` : "";
  return `<button type="button" class="btn ${o.size || ""}" ${attrs}>${ico}${label}</button>`;
}
function mode(kind, text) { return `<span class="mode ${kind}">${esc(text)}</span>`; }
function frame({ id = "", title = "", body = "", x, y, w, cls = "", close = true, after = "" }) {
  return `<section class="frame ${cls}" ${id ? `id="${id}"` : ""} style="left:${x}px;top:${y}px;width:${w}px" aria-label="${esc(title.replace(/<[^>]+>/g, ""))}">
    ${title ? `<div class="frame-header">${title}</div>` : ""}
    ${close ? `<button type="button" class="frame-close" aria-label="Close" data-goto="__close"></button>` : ""}
    ${body}${after}</section>`;
}
function tip(html, x, y, w) { return `<div class="tip" style="left:${x}px;top:${y}px;${w ? `width:${w}px` : ""}">${html}</div>`; }

/* ---------- Chat frame ---------- */
const CHAT_BASE = [
  ["sys", "Lucifron has been defeated."],
];
function chatLine(kind, html) { return `<div class="chat-line ${kind}">${html}</div>`; }
function raidLine(text, code, practice) {
  return chatLine("rl", `[Raid Leader] [${who(LM)}]: ${practice ? "[Practice] " : ""}${text}${code ? ` <span class="code">${CODE(code)}</span>` : ""}`);
}
function rwLine(text, practice) { return chatLine("rw", `[Raid Warning] [${who(LM)}]: ${practice ? "[Practice] " : ""}${text}`); }
function sysLine(text) { return chatLine("sys", text); }
function lootLine(name, key) { return chatLine("add", `${who(name)} receives loot: ${link(key)}.`); }
function chat(lines) {
  return `<div class="chat" aria-label="Chat"><span class="chat-tab">General</span><div class="chat-body">${lines.join("")}</div></div>`;
}

/* ---------- Minimap with the add-on's button ---------- */
function minimap(o = {}) {
  const badge = o.badge ? `<span class="mm-badge">${o.badge}</span>` : "";
  return `<div class="minimap" aria-hidden="false"><div class="map"></div><div class="ring"></div><div class="zone">Molten Core</div>
    <button type="button" class="mm-btn" style="left:6px;top:116px" data-goto="awards" aria-label="Bureaucracy Forever: open the window">
      <span class="mm-ico" style="background-image:url(${ICON("inv_misc_book_09")})"></span><span class="mm-ring"></span>${badge}</button></div>`;
}

/* ---------- The game's own loot window ---------- */
function lootframe(keys, o = {}) {
  const page = o.page || 0, pages = Math.ceil(keys.length / 4);
  const slots = keys.slice(page * 4, page * 4 + 4).map((k) => `<div class="lf-slot" data-slot>${icon(k)}<span class="lf-name q-${ITEMS[k].q}">${esc(ITEMS[k].name)}</span></div>`).join("");
  const arrow = (to, ch, label) => `<button type="button" class="lf-arrow" data-page="${to}" aria-label="${label}">${ch}</button>`;
  const pager = pages > 1 ? `<div class="lf-page">${page > 0 ? arrow(page - 1, "◀", "Previous loot page") : ""}<span>Page ${page + 1} of ${pages}</span>${page < pages - 1 ? arrow(page + 1, "▶", "Next loot page") : ""}</div>` : "";
  return `<div class="lootframe" style="left:${o.x ?? 60}px;top:${o.y ?? 210}px" aria-label="The game's loot window">
    <div class="lf-portrait"></div><div class="lf-title">${esc(o.title || "Items")}</div><div class="lf-slots">${slots}</div>${pager}</div>`;
}

/* ---------- Pop-up content model ----------
   A corpse is { boss, items:[entry] }. Each entry says what the rules decided and what stage it's in.
   Versions only decide layout. */
function corpse(id) {
  const C = {};
  C.typical = {
    boss: "Lucifron", loot: ["choker", "gloves", "gauntlets"], items: [
      { key: "choker", kind: "hr", label: "Hard reserve", winner: "Ashla Brightwater", contenders: ["Ashla Brightwater"], action: "give" },
      { key: "gloves", kind: "sr", label: "Soft reserve", winner: "Doran Vale", contenders: ["Doran Vale"], action: "give" },
      { key: "gauntlets", kind: "open", label: "Open roll", note: "Nobody reserved it", action: "openroll" },
    ],
  };
  C.crowded = {
    boss: "Magmadar", loot: ["robe", "ring", "wrist", "wrist", "core", "belt"], items: [
      { key: "robe", kind: "hr", label: "Hard reserve roll-off", contenders: ["Ashla Brightwater", "Mirel Stone", "Tovin Hale", "Ysolde Marr"],
        skipped: [["Kessa Moorfield", "not in raid"], ["Lyra Dawnmere", "trial: shown, doesn't roll"]], action: "roll" },
      { key: "ring", kind: "sr", label: "Soft reserve roll-off", contenders: ["Doran Vale", "Celwen Thorne", "Rhona Teague", "Edric Moss", "Fenna Lark", "Quill Ashby", "Wren Calder"],
        skipped: [["Vena Holt", "the game won't let them receive this item (usually: not nearby when the boss died)"]], action: "roll" },
      { key: "wrist", copy: "Copy 1 of 2", kind: "hr", label: "Hard reserve", winner: "Bram Ironvein", contenders: ["Bram Ironvein"], action: "give" },
      { key: "wrist", copy: "Copy 2 of 2", kind: "sr", label: "Soft reserve roll-off", note: "Copy 1 goes to the hard reserve", contenders: ["Celwen Thorne", "Garrick Fenn"], action: "roll" },
      { key: "core", kind: "open", label: "Open roll", note: "Not on the raid's loot list", action: "openroll" },
      { key: "belt", kind: "sr", label: "Soft reserve", winner: "Pell Harrow", contenders: ["Pell Harrow"],
        skipped: [["Ostrin Pike", "hard reserve already received tonight"]], action: "give" },
    ],
  };
  return JSON.parse(JSON.stringify(C[id]));
}
/* Variants of a corpse for each pop-up state */
function popupModel(state) {
  let m;
  switch (state) {
    case "popup-typical": return corpse("typical");
    case "popup-crowded": return corpse("crowded");
    case "popup-page2": m = corpse("crowded"); m.page = 1; return m;
    case "popup-boss": m = corpse("typical"); m.boss = "Trash"; m.bossMenu = true; m.bossNote = "These items drop from more than one boss. Pick the boss before awarding."; return m;
    case "popup-no-reserves": m = corpse("typical"); m.noReserves = true;
      m.items.forEach((e) => { e.kind = "open"; e.label = "Open roll"; e.note = "No reserves loaded"; e.action = "openroll"; delete e.winner; delete e.contenders; }); return m;
    case "popup-fight": m = corpse("typical"); m.fight = true; return m;
    case "popup-unavailable": m = corpse("typical");
      m.items[0].winner = "Unknown"; m.items[0].unavailable = "Ashla Brightwater's name hasn't loaded yet (shown as \"Unknown\"). Try again in a moment.";
      m.items[1].skipped = [["Doran Vale", "the game won't let them receive this item (usually: not nearby when the boss died)"]];
      m.items[1].kind = "open"; m.items[1].label = "Open roll"; m.items[1].note = "No one else reserved it"; m.items[1].action = "openroll"; delete m.items[1].winner; m.items[1].contenders = [];
      return m;
    case "popup-db": m = corpse("typical"); m.dbMenu = 2; return m;
    case "roll-called": m = corpse("crowded"); m.focus = 0;
      Object.assign(m.items[0], { stage: "rolling", rolls: [["Mirel Stone", 87], ["Ashla Brightwater", 42], ["Ysolde Marr", 15]], waiting: ["Tovin Hale"],
        ignored: [["Quill Ashby", 99, "not eligible"], ["Ashla Brightwater", 96, "second roll, the first counts"]] }); return m;
    case "roll-tie": m = corpse("crowded"); m.focus = 0;
      Object.assign(m.items[0], { stage: "tie", rolls: [["Mirel Stone", 87], ["Tovin Hale", 87], ["Ashla Brightwater", 42], ["Ysolde Marr", 15]], tie: ["Mirel Stone", "Tovin Hale"] }); return m;
    case "roll-hidden": m = corpse("crowded"); m.focus = 0; Object.assign(m.items[0], { stage: "hidden" }); return m;
    case "handout-waiting": m = corpse("typical"); m.focus = 0; m.items[0].stage = "waiting"; return m;
    case "not-confirmed": m = corpse("typical"); m.focus = 0; m.items[0].stage = "notconfirmed"; return m;
    case "give-else": m = corpse("typical"); m.focus = 0; m.items[0].stage = "giveelse"; return m;
    case "practice": m = corpse("typical"); m.practice = true; m.boss = "Test drop"; m.testDrop = true;
      m.items[0].winner = "Konvett Konvett"; m.items[0].contenders = ["Konvett Konvett"];
      m.items[1].kind = "hr"; m.items[1].label = "Hard reserve roll-off"; m.items[1].action = "roll"; m.items[1].contenders = ["Konvett Konvett", "Seraphine Ashdown"]; delete m.items[1].winner;
      return m;
  }
  return null;
}

/* Chat lines shown for each state (the wording agreed in Q7) */
function chatFor(state) {
  const L = [sysLine("Lucifron has been defeated.")];
  switch (state) {
    case "popup-crowded": case "roll-hidden": return [sysLine("Magmadar has been defeated.")];
    case "roll-called": return [sysLine("Magmadar has been defeated."), rwLine(`Roll for ${link("robe")}: Ashla Brightwater, Mirel Stone, Tovin Hale, Ysolde Marr (hard reserve)`),
      sysLine("Mirel Stone rolls 87 (1-100)"), sysLine("Quill Ashby rolls 99 (1-100)"), sysLine("Ashla Brightwater rolls 42 (1-100)"), sysLine("Ysolde Marr rolls 15 (1-100)"), sysLine("Ashla Brightwater rolls 96 (1-100)")];
    case "roll-tie": return [sysLine("Magmadar has been defeated."), rwLine(`Roll for ${link("robe")}: Ashla Brightwater, Mirel Stone, Tovin Hale, Ysolde Marr (hard reserve)`),
      sysLine("Mirel Stone rolls 87 (1-100)"), sysLine("Tovin Hale rolls 87 (1-100)"), sysLine("Ashla Brightwater rolls 42 (1-100)"), sysLine("Ysolde Marr rolls 15 (1-100)")];
    case "handout-waiting": return [...L, raidLine(`${link("choker")} → Ashla Brightwater (hard reserve)`, "19-4410")];
    case "not-confirmed": return [...L, raidLine(`${link("choker")} → Ashla Brightwater (hard reserve)`, "19-4410")];
    case "give-else": return [...L, raidLine(`${link("choker")} → Ashla Brightwater (hard reserve)`, "19-4410")];
    case "popup-fight": return [...L, sysLine("Magmadar engaged. Chat is restricted for add-ons until the fight ends.")];
    case "practice": return [sysLine("Practice mode on: reserves are made up, and nothing is sent to the guild site."),
      rwLine(`Roll for ${link("gloves")}: Konvett Konvett, Seraphine Ashdown (hard reserve)`, true)];
    case "awards": case "awards-officer": return [raidLine(`Undo: ${link("belt")} is no longer awarded to Pell Harrow`, "31-0007"),
      raidLine(`${link("core")} → Lyra Dawnmere (open roll, 66)`, "40-1108"), lootLine("Lyra Dawnmere", "core")];
    case "outside-handout": return [...L, lootLine("Ashla Brightwater", "choker")];
    case "notice-handover": return [sysLine("Seraphine Ashdown is now the loot master.")];
    default: return L;
  }
}

/* ---------- Officers' window ---------- */
const AWARDS = [
  { t: "20:02", boss: "Lucifron", key: "choker", who: "Ashla Brightwater", how: "Hard reserve" },
  { t: "20:02", boss: "Lucifron", key: "gloves", who: "Doran Vale", how: "Soft reserve" },
  { t: "20:03", boss: "Lucifron", key: "gauntlets", who: "Bram Ironvein", how: "Open roll", roll: 91 },
  { t: "20:15", boss: "Magmadar", key: "robe", who: "Mirel Stone", how: "Hard reserve", roll: 87 },
  { t: "20:15", boss: "Magmadar", key: "ring", who: "Tovin Hale", how: "Soft reserve", roll: 74, status: "notconfirmed" },
  { t: "20:16", boss: "Magmadar", key: "wrist", who: "Bram Ironvein", how: "Hard reserve" },
  { t: "20:16", boss: "Magmadar", key: "wrist", who: "Edric Moss", how: "Disenchant/bank" },
  { t: "20:31", boss: "Gehennas", key: "belt", who: "Pell Harrow", how: "Soft reserve", status: "undone", note: "Undone 20:33" },
  { t: "20:33", boss: "Gehennas", key: "belt", who: "", how: "", status: "needswinner", note: "Undone after it left the corpse" },
  { t: "20:34", boss: "Gehennas", key: "helm", who: "Rhona Teague", how: "Open roll", roll: 58 },
  { t: "20:40", boss: "Trash", key: "core", who: "Lyra Dawnmere", how: "Open roll", roll: 66 },
  { t: "20:52", boss: "Garr", key: "boots", who: "Ysolde Marr", how: "Hard reserve" },
];
const PRACTICE_AWARDS = [
  { t: "Sun 19:12", boss: "Edwin VanCleef", key: "gauntlets", who: "Seraphine Ashdown", how: "Hard reserve" },
  { t: "Sun 19:13", boss: "Edwin VanCleef", key: "boots", who: "Konvett Konvett", how: "Open roll", roll: 77 },
];

function awardActions(a, readOnly) {
  const dis = readOnly ? { disabled: true, title: "Only the loot master (Konvett Konvett) can change awards." } : {};
  if (a.status === "notconfirmed") return `<div class="btn-row">${btn("Try again", { size: "tiny", ...dis })}${btn("Someone else", { size: "tiny", ...dis, goto: readOnly ? "" : "give-else" })}${btn("Not handed out", { size: "tiny", ...dis })}</div>`;
  if (a.status === "needswinner") return btn("Pick winner", { size: "tiny", ...dis });
  if (a.status === "undone") return `<span class="grey small narrow">${esc(a.note)}</span>`;
  if (a.status === "noraid") return "";
  return btn("Undo", { size: "tiny", ...dis });
}
function awardWinner(a) {
  if (a.status === "needswinner") return `${mode("warn", "Needs a winner")} <span class="hint">${esc(a.note)}</span>`;
  if (a.status === "notconfirmed") return `${who(a.who)} ${mode("warn", "Not confirmed")}`;
  if (a.status === "undone") return who(a.who, { struck: true });
  return who(a.who);
}
function awardRow(a, readOnly, showBoss = true) {
  const cls = a.status === "undone" ? "void" : a.status === "notconfirmed" || a.status === "needswinner" ? "hl" : "";
  return `<tr class="${cls}"><td class="grey">${a.t}</td>${showBoss ? `<td>${esc(a.boss)}</td>` : ""}
    <td style="white-space:nowrap"><span class="item-cell">${icon(a.key, "s")}${link(a.key)}</span></td><td>${awardWinner(a)}</td>
    <td class="${a.status === "undone" ? "struck" : ""}">${esc(a.how)}</td><td>${a.roll ?? ""}</td><td style="text-align:right">${awardActions(a, readOnly)}</td></tr>`;
}

function windowFrame(tab, body, o = {}) {
  const tabs = ["Awards", "Reserves", "Sync"].map((t) => {
    const id = t.toLowerCase(); const target = id === "awards" ? (o.readOnly ? "awards-officer" : "awards") : id === "reserves" ? "reserves" : "sync-loaded";
    return `<button type="button" class="tab ${tab === id ? "active" : ""}" data-goto="${target}" aria-pressed="${tab === id}">${t}</button>`;
  }).join("");
  const practice = o.practice;
  const footer = `<div class="row" style="margin-top:10px;font-family:ArialN,sans-serif;font-size:13px">
      <span class="muted">Loot master: ${who(LM)}${o.readOnly ? "" : " (you)"}</span><span class="spacer"></span>
      <label class="row" style="gap:4px"><img alt="" src="${practice ? ASSET.check : ASSET.checkUp}" width="22" height="22" style="background:url(${ASSET.checkUp}) 0 0/22px"> <span class="gold" style="font-family:Friz,serif;font-size:12px">Practice mode</span></label>
      ${btn("Test drop", { size: "tiny", goto: "practice" })}</div>`;
  const title = practice ? `[Practice] Bureaucracy Forever` : `Bureaucracy Forever`;
  return frame({ id: "window", title, x: o.x ?? 380, y: o.y ?? 110, w: o.w ?? 840, body: `<div style="min-height:${o.minH ?? 420}px">${body}</div>${footer}`, after: `<nav class="tabs" aria-label="Window tabs">${tabs}</nav>` });
}

function awardsBody(grouped, readOnly, empty) {
  if (empty) return `<div class="col" style="align-items:center;justify-content:center;min-height:380px;text-align:center">
      <div class="gold" style="font-size:15px">No awards yet this raid</div>
      <div class="hint" style="max-width:380px">Items you hand out with the pop-up, or from the game's loot menu, show up here with the time, boss, winner and how they won.</div></div>`;
  const note = readOnly ? `<div class="note-bar" style="margin-bottom:8px">Only the loot master (${who(LM)}) can change awards. This list updates as they hand items out.</div>` : "";
  const head = `<tr><th>Time</th>${grouped ? "" : "<th>Boss</th>"}<th>Item</th><th>Winner</th><th>How</th><th>Roll</th><th></th></tr>`;
  let rows = "";
  if (grouped) {
    let last = "";
    for (const a of AWARDS) { if (a.boss !== last) { last = a.boss; const n = AWARDS.filter((x) => x.boss === a.boss).length; rows += `<tr class="group"><td colspan="6">${esc(a.boss)} <span class="grey small narrow">· ${n} item${n > 1 ? "s" : ""}</span></td></tr>`; } rows += awardRow(a, readOnly, false); }
  } else rows = AWARDS.map((a) => awardRow(a, readOnly)).join("");
  const prac = `<details style="margin-top:10px"><summary class="gold" style="cursor:pointer;font-size:12px">Practice awards (2) · never sent to the guild site</summary>
      <table class="list"><tbody>${PRACTICE_AWARDS.map((a) => `<tr><td class="grey">${a.t}</td><td>${esc(a.boss)}</td><td><span class="item-cell">${icon(a.key, "s")}${link(a.key)}</span></td><td>${who(a.who)}</td><td>${esc(a.how)}</td><td>${a.roll ?? ""}</td><td>${mode("practice", "Practice")}</td></tr>`).join("")}</tbody></table></details>`;
  const summary = `<div class="row hint" style="margin-bottom:6px"><span>12 awards · <span class="amber">1 not confirmed</span> · <span class="amber">1 needs a winner</span></span><span class="spacer"></span><span>Sent to the site by the helper: 20:41</span></div>`;
  return `${note}${summary}<table class="list"><thead>${head}</thead><tbody>${rows}</tbody></table>${prac}`;
}

const RESERVES = [
  { boss: "Lucifron", killed: true, items: [
    { key: "choker", hr: [["Ashla Brightwater", "got"]], sr: [["Doran Vale"], ["Mirel Stone", "absent"]] },
    { key: "gloves", hr: [], sr: [["Doran Vale", "got"], ["Ysolde Marr"]] },
  ] },
  { boss: "Magmadar", killed: true, items: [
    { key: "robe", hr: [["Ashla Brightwater"], ["Mirel Stone", "got"], ["Tovin Hale"], ["Ysolde Marr"], ["Kessa Moorfield", "absent"], ["Lyra Dawnmere", "trial"]], sr: [] },
    { key: "ring", hr: [], sr: [["Doran Vale"], ["Celwen Thorne"], ["Rhona Teague"], ["Edric Moss"], ["Fenna Lark"], ["Quill Ashby"], ["Wren Calder"], ["Vena Holt"]] },
    { key: "wrist", hr: [["Bram Ironvein", "got"]], sr: [["Celwen Thorne"], ["Garrick Fenn"]] },
  ] },
  { boss: "Gehennas", killed: true, items: [
    { key: "belt", hr: [["Ostrin Pike", "got"]], sr: [["Pell Harrow"]] },
    { key: "helm", hr: [["Silas Crane", "absent"]], sr: [] },
  ] },
  { boss: "Garr", killed: false, items: [
    { key: "boots", hr: [["Ysolde Marr", "got"]], sr: [["Hollis Grey"], ["Ardan Vey"]] },
  ] },
];
function resName([n, flag]) {
  if (flag === "got") return `<span>${who(n)} <span class="tick" title="Received">✓</span></span>`;
  if (flag === "absent") return `<span title="Not in raid">${who(n, { absent: true })}</span>`;
  if (flag === "trial") return `<span>${who(n)} <span class="grey small">(trial)</span></span>`;
  return who(n);
}
function reservesBody(empty) {
  if (empty) return `<div class="col" style="align-items:center;justify-content:center;min-height:380px;text-align:center">
      <div class="gold" style="font-size:15px">No reserves loaded</div>
      <div class="hint" style="max-width:380px">Paste the raid's reserves on the Sync tab, or start the desktop helper and type /reload.</div>
      <div style="margin-top:8px">${btn("Go to Sync", { goto: "sync-empty" })}</div></div>`;
  const legend = `<div class="row hint" style="margin-bottom:6px;gap:14px"><span><span class="tick">✓</span> received</span><span class="grey">Grey: not in raid</span><span>(trial): shown, doesn't roll</span><span class="spacer"></span><span>${esc(RAID)} · 38 players · 61 reserves</span></div>`;
  let rows = "";
  for (const b of RESERVES) {
    rows += `<tr class="group"><td colspan="3">${esc(b.boss)} ${b.killed ? `<span class="grey small narrow">· killed</span>` : ""}</td></tr>`;
    for (const it of b.items) rows += `<tr><td style="width:34%"><span class="item-cell">${icon(it.key, "s")}${link(it.key)}</span></td>
      <td style="width:28%">${it.hr.length ? it.hr.map(resName).join(", ") : '<span class="grey">-</span>'}</td>
      <td>${it.sr.length ? it.sr.map(resName).join(", ") : '<span class="grey">-</span>'}</td></tr>`;
  }
  return `${legend}<table class="list"><thead><tr><th>Item</th><th>Hard reserve</th><th>Soft reserve</th></tr></thead><tbody>${rows}</tbody></table>`;
}

function syncBody(kind) {
  const paste = (val, extra = "") => `<div class="gold" style="margin:2px 0 4px">Reserves in</div>
    <div class="hint" style="margin-bottom:4px">On the guild site, open the raid and choose <b class="white">Copy for the add-on</b>. Paste it here with Ctrl+V (Cmd+V on Mac).</div>
    <textarea class="input" rows="3" aria-label="Paste reserves" placeholder="Paste the reserves text here">${val}</textarea>
    <div class="row" style="margin-top:6px">${btn("Load", { goto: kind === "sync-empty" ? "sync-loaded" : "" })}${extra}</div>`;
  const loaded = `<div class="note-bar good">Loaded: <b>${esc(RAID)}</b> · 38 players · 61 reserves. Copied from the site 19:42, loaded 19:50.</div>`;
  const helper = `<div class="row hint" style="margin-top:6px"><img class="dot" alt="" src="${ASSET.dotGreen}"> Desktop helper in use: reserves arrive at login or /reload, and awards go to the site live.</div>`;
  const out = (enabled) => `<div class="hr-div" style="margin:12px 0 6px"></div><div class="gold" style="margin-bottom:4px">Awards out</div>
    <div class="hint" style="margin-bottom:6px">Only needed if the desktop helper isn't running. Paste the text into the raid's loot log on the guild site (Import from the add-on).</div>
    <div class="row">${btn("Copy awards", { disabled: !enabled })}<span class="hint">${enabled ? "12 awards, 1 undo. Practice awards are never included." : "Nothing to copy yet."}</span></div>`;
  switch (kind) {
    case "sync-empty": return `<div class="note-bar warn" style="margin-bottom:8px">No reserves loaded. The pop-up still works, but every item is an open roll.</div>${paste("")}${out(false)}`;
    case "sync-loaded": return `${loaded}${helper}<div style="height:8px"></div>${paste("")}
      <div class="hr-div" style="margin:12px 0 6px"></div><div class="gold" style="margin-bottom:4px">Awards out</div>
      <div class="hint" style="margin-bottom:6px">Only needed if the desktop helper isn't running. The text is selected: press Ctrl+C (Cmd+C on Mac), then paste it into the raid's loot log on the guild site (Import from the add-on).</div>
      <textarea class="input selected-text" rows="2" aria-label="Awards to copy" readonly>BFA1:A7K2:MC-20261210:eyJ2IjoxLCJhIjpbWyIxOS00NDEwIiwyMDAyLCJMdWNpZnJvbiIsMTk4MzcsIkFzaGxhIEJyaWdodHdhdGVyIiwiSFIiXSxbIjE5LTQ0MTEiLDIwMDIs...</textarea>
      <div class="row" style="margin-top:6px">${btn("Copy awards")}<span class="hint">12 awards, 1 undo. Practice awards are never included.</span></div>`;
    case "sync-refused": return `${paste("BFR3:MC-20261217:eyJ2IjozLCJy...", "")}
      <div class="note-bar bad" style="margin-top:8px">This text needs a newer version of the add-on (you have 1.2.1). Nothing was loaded; your current reserves are unchanged.</div>
      <div class="row" style="margin-top:6px"><span class="hint">Download link:</span><input class="input selected-text" style="flex:1" readonly aria-label="Download link" value="https://github.com/robpaolella/bureaucracy-forever-addon/releases/latest"></div>
      <div class="hint" style="margin-top:4px">Press Ctrl+C to copy the link, open it in your browser, replace the add-on folder, then /reload.</div>${out(true)}`;
    case "sync-switch": return `${loaded}${helper}<div style="height:8px"></div>${paste("BFR1:BWL-20261213:eyJ2IjoxLCJy...")}${out(true)}`;
    case "sync-noraid": return `<div class="note-bar warn" style="margin-bottom:8px"><b>3 awards aren't linked to a raid.</b> They were made before reserves were loaded, so they can't be sent to the site yet.</div>
      <table class="list"><tbody>
        <tr><td class="grey">19:58</td><td>Trash</td><td><span class="item-cell">${icon("core", "s")}${link("core")}</span></td><td>${who("Quill Ashby")}</td><td>Open roll</td><td>82</td></tr>
        <tr><td class="grey">20:02</td><td>Lucifron</td><td><span class="item-cell">${icon("choker", "s")}${link("choker")}</span></td><td>${who("Ashla Brightwater")}</td><td>Open roll</td><td>71</td></tr>
        <tr><td class="grey">20:02</td><td>Lucifron</td><td><span class="item-cell">${icon("gloves", "s")}${link("gloves")}</span></td><td>${who("Doran Vale")}</td><td>Open roll</td><td>64</td></tr>
      </tbody></table>
      <div class="row" style="margin:8px 0 12px">${btn(`Attach to ${esc(RAID)}`)}<span class="hint">Methods stay as recorded. Fix any on the site afterwards.</span></div>
      ${loaded}${out(true)}`;
  }
}

/* ---------- Notices ---------- */
function notice(body, buttons, o = {}) {
  return `<section class="frame notice ${o.gold ? "gold-border" : ""}" style="top:${o.top ?? 150}px;width:${o.w ?? 440}px" role="dialog" aria-label="${esc(o.label || "Notice")}">${body}<div class="btn-row">${buttons}</div></section>`;
}
function tooltipHTML(key, lines) {
  const it = ITEMS[key];
  return `<div class="q-${it.q}" style="font-family:Friz,serif;font-size:14px">${esc(it.name)}</div><div>Binds when picked up</div><div class="row"><span>${esc(it.slot.split(" · ")[0])}</span><span class="spacer"></span><span>${esc(it.slot.split(" · ")[1] || "")}</span></div>
    ${it.stats.map((s) => `<div class="${s.startsWith("Equip") ? "green" : ""}">${esc(s)}</div>`).join("")}${lines}`;
}

/* ---------- Scene assembly and switcher ---------- */
const GROUPS = [
  ["Pop-up", ["popup-typical", "popup-crowded", "popup-page2", "popup-boss", "popup-no-reserves", "popup-fight", "popup-unavailable", "popup-db"]],
  ["Roll-offs", ["roll-called", "roll-tie", "roll-hidden"]],
  ["Hand-outs", ["handout-waiting", "not-confirmed", "give-else"]],
  ["Awards tab", ["awards", "awards-empty", "awards-officer"]],
  ["Reserves tab", ["reserves", "reserves-empty", "tooltip"]],
  ["Sync tab", ["sync-empty", "sync-loaded", "sync-refused", "sync-switch", "sync-noraid"]],
  ["Practice and notices", ["practice", "notice-update", "notice-handover", "outside-handout", "minimap"]],
];
const LABELS = {
  "popup-typical": "Typical corpse", "popup-crowded": "Crowded corpse (worst case)", "popup-page2": "Crowded corpse, loot window page 2", "popup-boss": "Choose the boss", "popup-no-reserves": "No reserves loaded",
  "popup-fight": "Boss fight: waiting", "popup-unavailable": "Winner can't be given the item", "popup-db": "Disenchant/bank list",
  "roll-called": "Rolls coming in", "roll-tie": "Tie", "roll-hidden": "Rolls hidden",
  "handout-waiting": "Handing out", "not-confirmed": "Not confirmed", "give-else": "Give to someone else",
  awards: "Awards", "awards-empty": "Awards: empty", "awards-officer": "Awards: another officer",
  reserves: "Reserves", "reserves-empty": "Reserves: none loaded", tooltip: "Item tooltip",
  "sync-empty": "Sync: nothing loaded", "sync-loaded": "Sync: loaded, copy out", "sync-refused": "Sync: paste refused", "sync-switch": "Sync: switch raid", "sync-noraid": "Sync: awards with no raid",
  practice: "Practice mode and Test drop", "notice-update": "Update notice", "notice-handover": "Loot master handover", "outside-handout": "Given from the game's menu", minimap: "Minimap button",
};
const STATE_IDS = GROUPS.flatMap((g) => g[1]);

/* Local view changes inside a state: which item is picked, which loot page shows. Reset on every state change. */
let VIEW = {};
function sceneFor(state, V) {
  let out = "";
  const pm = state === "practice" ? null : popupModel(state);
  if (pm) {
    Object.assign(pm, VIEW);
    out += V.popup(pm, state);
    out += chat(chatFor(state === "popup-page2" ? "popup-crowded" : state));
    out += minimap({ badge: 0 });
    return out;
  }
  switch (state) {
    case "awards": out += windowFrame("awards", awardsBody(V.groupAwards, false)); break;
    case "awards-empty": out += windowFrame("awards", awardsBody(V.groupAwards, false, true)); break;
    case "awards-officer": out += windowFrame("awards", awardsBody(V.groupAwards, true), { readOnly: true }); break;
    case "reserves": out += windowFrame("reserves", reservesBody(false)); break;
    case "reserves-empty": out += windowFrame("reserves", reservesBody(true)); break;
    case "tooltip": out += chat([raidLine(`${link("choker")} → Ashla Brightwater (hard reserve)`, "19-4410"), raidLine(`Anyone need ${link("robe")}?`)]) +
      tip(tooltipHTML("robe", `<div class="hr-div" style="margin:4px 0"></div><div class="gold" style="font-family:Friz,serif;font-size:12px">Bureaucracy reserves</div>
        <div>Hard: ${who("Ashla Brightwater")}, ${who("Mirel Stone")} <span class="tick">✓</span>, ${who("Tovin Hale")}, ${who("Ysolde Marr")}, ${who("Kessa Moorfield", { absent: true })}, ${who("Lyra Dawnmere")} <span class="grey">(trial)</span></div>
        <div>Soft: <span class="grey">none</span></div>`), 360, 470, 330); break;
    case "sync-empty": case "sync-loaded": case "sync-refused": case "sync-noraid": out += windowFrame("sync", syncBody(state)); break;
    case "sync-switch": out += windowFrame("sync", syncBody(state)) + notice(`<p>Load reserves for <b class="white">Blackwing Lair, Sun 13 Dec</b>?</p><p class="hint">You have 12 awards for ${esc(RAID)}. They stay with that raid and are still sent to the site.</p>`,
      btn("Load", { goto: "sync-loaded" }) + btn("Cancel", { goto: "sync-loaded" }), { top: 260, label: "Switch raid" }); break;
    case "practice": { const pm2 = popupModel("practice"); out += windowFrame("awards", awardsBody(V.groupAwards, false), { practice: true, x: 610, y: 150, w: 620 }) + V.popup(pm2, "practice") + chat(chatFor("practice")); break; }
    case "notice-update": out += notice(`<div class="row" style="justify-content:center;gap:10px"><img alt="" src="${ASSET.alert}" width="36" height="36"><div style="text-align:left">A newer <b class="white">Bureaucracy Forever</b> is out: <b class="green">1.3.0</b> (you have 1.2.1).</div></div>
      <p class="hint">Copy the link (Ctrl+C), download it, replace the add-on folder, then /reload. The desktop helper updates it for you.</p>
      <input class="input selected-text" style="width:100%" readonly aria-label="Download link" value="https://github.com/robpaolella/bureaucracy-forever-addon/releases/latest"><div style="height:8px"></div>`,
      btn("Close", { goto: "awards" }), { label: "Update notice", w: 460 }) + chat([sysLine("Lucifron has been defeated.")]); break;
    case "notice-handover": out += notice(`<p><b class="white">You're now the loot master.</b></p><p class="hint">Konvett Konvett's 12 awards are loaded as history. Your add-on now hands out and records awards, and other officers' add-ons follow you.</p>`,
      btn("Open awards", { goto: "awards" }) + btn("OK", { goto: "__close" }), { label: "Loot master handover" }) + chat(chatFor(state)); break;
    case "outside-handout": out += lootframe(["choker", "gloves", "gauntlets"], { title: "Lucifron" }) + notice(`<p>You gave ${link("choker")} to ${who("Ashla Brightwater")} from the game's loot menu. How was it won?</p>
      <div class="col" style="text-align:left;margin:0 30px 10px;font-family:ArialN,sans-serif;font-size:14px">
        <label class="row"><input type="radio" name="how" checked> Hard reserve <span class="hint">(she hard-reserved it)</span></label>
        <label class="row"><input type="radio" name="how"> Soft reserve</label>
        <label class="row"><input type="radio" name="how"> Open roll, roll: <input class="input" style="width:60px" aria-label="Roll"></label>
        <label class="row"><input type="radio" name="how"> Disenchant/bank</label></div>
      <p class="hint">Recording it posts the award line in raid chat.</p>`, btn("Record and announce", { goto: "awards" }) + btn("Later", { goto: "awards" }), { label: "How was it won?", top: 200 }) + chat(chatFor(state)); break;
    case "minimap": out += minimap({ badge: 1 }) + tip(`<div class="white" style="font-family:Friz,serif">Bureaucracy Forever</div><div>${esc(RAID)}</div><div class="amber">1 hand-out not confirmed</div><div class="hint" style="margin-top:4px">Click: open the window<br>Drag: move the button</div>`, 1130, 160, 230); return out + chat(chatFor(state));
  }
  out += minimap({ badge: state.startsWith("awards") || state === "practice" ? 1 : 0 });
  return out;
}

function boot(V) {
  const params = new URLSearchParams(location.search);
  let state = STATE_IDS.includes(params.get("state")) ? params.get("state") : STATE_IDS[0];
  const theme = "default";
  const bar = document.getElementById("proto-bar");
  const opts = GROUPS.map(([g, ids]) => `<optgroup label="${g}">${ids.map((id) => `<option value="${id}">${LABELS[id]}</option>`).join("")}</optgroup>`).join("");
  bar.innerHTML = `<strong>Prototype controls (not part of the add-on)</strong>
    <span>Version ${V.letter}: ${V.name}</span>
    <label>State <select id="state-select">${opts}</select></label>
    <button type="button" id="prev">◀ Previous</button><button type="button" id="next">Next ▶</button>
    <label>Theme <select id="theme-select"><option value="default">Default (the game has one look)</option></select></label>
    <span class="proto-note">${V.blurb} Buttons inside the game windows move between states where it makes sense.</span>`;
  const sel = document.getElementById("state-select");
  const scene = document.getElementById("scene");
  function fit() {
    const vw = document.documentElement.clientWidth; const s = Math.min(1, vw / 1440);
    let h = 900; const top = scene.getBoundingClientRect().top;
    scene.style.height = "auto";
    for (const el of scene.querySelectorAll(".frame, .tip, .chat, .lootframe")) h = Math.max(h, (el.getBoundingClientRect().bottom - top) / s + 70);
    scene.style.height = h + "px";
    scene.style.transform = `scale(${s})`; document.getElementById("viewport").style.height = h * s + "px";
  }
  function render(push) {
    if (push !== "view") VIEW = {};
    scene.innerHTML = `<div class="scene-caption">${esc(LABELS[state])}</div>` + sceneFor(state, V);
    sel.value = state;
    const u = new URL(location.href); u.searchParams.set("state", state); u.searchParams.set("theme", theme);
    if (push) history.replaceState(null, "", u);
    fit();
    document.documentElement.dataset.state = state; document.documentElement.dataset.theme = theme;
  }
  sel.addEventListener("change", () => { state = sel.value; render(true); });
  document.getElementById("prev").addEventListener("click", () => { state = STATE_IDS[(STATE_IDS.indexOf(state) + STATE_IDS.length - 1) % STATE_IDS.length]; render(true); });
  document.getElementById("next").addEventListener("click", () => { state = STATE_IDS[(STATE_IDS.indexOf(state) + 1) % STATE_IDS.length]; render(true); });
  scene.addEventListener("click", (e) => {
    const v = e.target.closest("[data-focus], [data-page]");
    if (v && !v.disabled) {
      if (v.dataset.focus !== undefined) VIEW.focus = Number(v.dataset.focus);
      if (v.dataset.page !== undefined) { VIEW.page = Number(v.dataset.page); delete VIEW.focus; }
      render("view"); return;
    }
    const t = e.target.closest("[data-goto]"); if (!t || t.disabled) return;
    const g = t.dataset.goto; if (!g) return;
    if (g === "__close") { const f = t.closest(".frame"); if (f) f.style.display = "none"; return; }
    if (STATE_IDS.includes(g)) { state = g; render(true); }
  });
  window.addEventListener("resize", fit);
  render(false);
}
