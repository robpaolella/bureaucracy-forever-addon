/* Revision 3: what the Awards tab's Pick winner opens (#115, covers #40).
   Sample data only. Shared content; each version (PW_V) decides only where the picker sits. */

const PW_PREV = "Pell Harrow";            /* who had the item before it was undone */
const PW_TIME = "20:47";
const PW_RAIDCODE = "k7m2x";
/* The item's reserve holders other than the previous winner. Holders who already received it
   tonight (Ostrin Pike's hard reserve) are left out, as on the pop-up's give-else list. */
const PW_HOLDERS = {
  typical: [["Hollis Grey", "SR"], ["Ardan Vey", "SR", "not in raid"]],
  none: [],
  crowded: [["Garrick Fenn", "HR"], ["Bellis Rook", "HR"], ["Corwin Slate", "HR", "not in raid"],
    ["Hollis Grey", "SR"], ["Celwen Thorne", "SR"], ["Quill Ashby", "SR"], ["Wren Calder", "SR"], ["Fenna Lark", "SR"],
    ["Ardan Vey", "SR", "not in raid"], ["Silas Crane", "SR", "not in raid"]],
};
const PW_NOT_IN_RAID = ["Ardan Vey", "Corwin Slate", "Silas Crane", "Kessa Moorfield"];
const PW_MEMBERS = Object.keys(PEOPLE).filter((n) => n !== PW_PREV && !PW_NOT_IN_RAID.includes(n)).sort();
const PW_METHOD = { HR: ["hr", "Hard reserve"], SR: ["sr", "Soft reserve"], OPEN_ROLL: ["open", "Open roll"], DISENCHANT_BANK: ["db", "Disenchant/bank"] };
const PW_HOW = { HR: "hard reserve", SR: "soft reserve" };

/* What each state starts with. VIEW.pw (local clicks and typing) overrides it. */
function pwBase(state) {
  const m = { open: true, pick: null, other: null, roll: "", holders: PW_HOLDERS.typical };
  switch (state) {
    case "pick-start": m.open = false; break;
    case "pick-reserve": m.pick = "Hollis Grey"; break;
    case "pick-roll": m.pick = "__other"; m.other = "Bellis Rook"; m.roll = "92"; break;
    case "pick-roll-missing": m.pick = "__other"; m.other = "Bellis Rook"; m.roll = "920"; break;
    case "pick-db": m.pick = "__db"; break;
    case "pick-again": m.pick = PW_PREV; break;
    case "pick-none": m.holders = PW_HOLDERS.none; break;
    case "pick-crowded": m.holders = PW_HOLDERS.crowded; break;
    case "pick-fight": m.pick = "Hollis Grey"; m.fight = true; break;
    case "pick-practice": m.pick = "Hollis Grey"; m.practice = true; break;
    case "pick-done": m.open = false; m.done = true; break;
    case "pick-unposted": m.open = false; m.done = true; m.unposted = true; break;
  }
  return m;
}
function pwModel(state) {
  const m = Object.assign(pwBase(state), VIEW.pw || {});
  if (m.note === undefined) m.note = m.pick === PW_PREV ? "" : "Traded by " + PW_PREV;
  m.holders = m.holders.map(([char, method, reason]) => ({ char, method, reason }));
  return m;
}

/* The new award the pick makes: { char, method, roll } or null; and why Post is not possible yet. */
function pwAward(m) {
  if (!m.pick) return { award: null, why: "Choose who gets it." };
  if (m.pick === "__db") return { award: { char: null, method: "DISENCHANT_BANK" } };
  if (m.pick === "__other") {
    if (!m.other) return { award: null, why: "Choose who it went to." };
    const r = String(m.roll).trim();
    if (!/^\d+$/.test(r) || +r < 1 || +r > 100) return { award: null, why: r === "" ? "Type their roll, 1 to 100." : "A roll is 1 to 100." };
    return { award: { char: m.other, method: "OPEN_ROLL", roll: +r } };
  }
  if (m.pick === PW_PREV) return { award: { char: PW_PREV, method: "SR" } };
  const h = m.holders.find((x) => x.char === m.pick);
  return { award: { char: h.char, method: h.method } };
}
/* The Replacement line, as OpText.BuildLine makes it (spec 9.2): human part, then the machine part. */
function pwLine(a, practice) {
  const target = a.char ? `${esc(a.char)} (${a.method === "OPEN_ROLL" ? "open roll, " + a.roll : PW_HOW[a.method] || "disenchant/bank"})` : "disenchant/bank";
  const human = `${practice ? "[Practice] " : ""}Correction: ${link("belt")} → ${target}, not ${esc(PW_PREV)}`;
  const machine = `&lt;${practice ? "BF1P" : "BF1"};R;${PW_RAIDCODE};rp-4f9c2a7e;aw-2b8d4e6f;aw-9c1e5a7b;16864;gh3n1;${a.method};${a.roll ?? ""};${esc(a.char || "")}&gt;`;
  return `${human} <span class="code">${machine}</span>`;
}
function pwUndoLine(practice) {
  return `${practice ? "[Practice] " : ""}Undo: ${link("belt")} is no longer awarded to ${esc(PW_PREV)} <span class="code">&lt;${practice ? "BF1P" : "BF1"};V;${PW_RAIDCODE};vd-3e8a1f2c;aw-2b8d4e6f&gt;</span>`;
}
function pwRaidLine(html) { return chatLine("rl", `[Raid Leader] [${who(LM)}]: ${html}`); }

/* ----- The picker's parts (the same in every version) ----- */
function pwRadio(on) { return `<span class="rb ${on ? "on" : ""}" aria-hidden="true"></span>`; }
function pwChoice(m, id, inner, o = {}) {
  const on = m.pick === id;
  if (o.disabled) return `<div class="pick pw-off" aria-disabled="true">${pwRadio(false)}${inner}</div>`;
  return `<div class="pick ${on ? "on" : ""}" role="radio" aria-checked="${on}" tabindex="0" data-pw-pick="${esc(id)}" data-focus="0">${pwRadio(on)}${inner}</div>`;
}
function pwOtherControls(m) {
  if (m.pick !== "__other") return "";
  const menu = m.menu ? `<div class="tip menu pw-menu" role="listbox" aria-label="Raid members"><div class="menu-title">Who has it now?</div>
      ${PW_MEMBERS.map((n) => `<div class="mi ${n === m.other ? "sel" : ""}" role="option" aria-selected="${n === m.other}" tabindex="0" data-pw-other="${esc(n)}" data-focus="0"><span class="chk ${n === m.other ? "on" : ""}"></span>${who(n)}</div>`).join("")}</div>` : "";
  const bad = m.pick === "__other" && m.other && pwAward(m).why;
  return `<div class="pw-sub">
      <span style="position:relative;display:inline-block"><button type="button" class="dd" aria-haspopup="listbox" aria-expanded="${!!m.menu}" data-pw-menu="1" data-focus="0">${m.other ? who(m.other) : '<span class="hint">Choose a raid member</span>'}</button>${menu}</span>
      <label class="row" style="gap:4px"><span class="hint">Roll</span><input class="input pw-roll ${bad ? "pw-bad" : ""}" style="width:52px" inputmode="numeric" maxlength="3" aria-label="Their roll, 1 to 100" value="${esc(m.roll)}"></label>
    </div>`;
}
function pwList(m) {
  const holders = m.holders.map((h) => {
    const [cls, label] = PW_METHOD[h.method];
    if (h.reason) return pwChoice(m, h.char, `<span class="pw-name">${who(h.char, { absent: true })}</span><span class="grey small">${esc(h.reason)}</span>`, { disabled: true });
    return pwChoice(m, h.char, `<span class="pw-name">${who(h.char)}</span>${mode(cls, label)}`);
  }).join("");
  const none = m.holders.length ? "" : `<div class="hint pw-empty">Nobody else reserved this item.</div>`;
  const tall = m.holders.length > 5 ? "pw-scroll" : "";
  return `<div class="pick-list pw-list" role="radiogroup" aria-label="Who gets it">
      <div class="gold small pw-head">Reserved it</div><div class="${tall}" ${tall ? 'tabindex="0" aria-label="Reserve holders"' : ""}>${holders}${none}</div>${tall ? `<div class="hint small" style="margin:2px 0 0 4px">▼ ${m.holders.length} reserve holders · scroll for more</div>` : ""}
      <div class="gold small pw-head">Anyone else</div>
      ${pwChoice(m, "__other", `<span class="pw-name white">Someone else in the raid</span>${mode("open", "Open roll")}`)}
      ${pwOtherControls(m)}
      ${pwChoice(m, "__db", `<span class="pw-name white">Disenchant/bank</span>${mode("db", "Disenchant/bank")}`)}
      ${pwChoice(m, PW_PREV, `<span class="pw-name">${who(PW_PREV)}</span>${mode("sr", "Soft reserve")}<span class="hint small pw-again">had it before: cancels the undo</span>`)}
    </div>`;
}
function pwNote(m) {
  return `<label class="pw-note"><span class="gold small">Note for the guild site <span class="hint">(optional, never posted in chat)</span></span>
      <input class="input pw-note-in" maxlength="200" aria-label="Note for the guild site" value="${esc(m.note)}" placeholder="For example: traded by ${esc(PW_PREV)}"></label>`;
}
function pwPreview(m) {
  const { award, why } = pwAward(m);
  const body = award ? `<div class="chat-line rl pw-line">${pwLine(award, m.practice)}</div>` : `<div class="hint pw-line">${esc(why)}</div>`;
  return `<div class="pw-preview" aria-live="polite"><div class="gold small">Posts in raid chat</div>${body}</div>`;
}
function pwButtons(m) {
  const { award, why } = pwAward(m);
  const lock = m.fight ? "Chat is locked until the fight ends." : "";
  const dis = !award || m.fight;
  return `${btn("Post correction", { goto: dis ? "" : "pick-done", disabled: dis, title: lock || why || "Records the winner and posts the line. No hand-out: the item has left the corpse." })}${btn("Cancel", { goto: "pick-start" })}
    ${lock ? `<span class="hint pw-why">${esc(lock)}</span>` : ""}`;
}
function pwIntro(m) {
  return `<p class="pw-intro">${link("belt")} was undone after ${who(PW_PREV)} already had it. Choose who has it now. Nothing is handed out: this records the winner and posts one correction line.</p>
    ${m.fight ? `<div class="note-bar warn" style="margin-bottom:6px">Boss fight in progress. The game locks chat for add-ons, so the correction waits until it ends.</div>` : ""}`;
}
function pwPanel(m) {
  return { body: `${pwIntro(m)}${pwList(m)}${pwNote(m)}${pwPreview(m)}`, buttons: pwButtons(m) };
}

/* ----- The Awards tab around it (revision 1's rows; the needs-a-winner row changes) ----- */
function pwRows(m) {
  const done = m.done ? (PW_POSTED.award || { char: "Hollis Grey", method: "SR" }) : null;
  if (!done) return AWARDS;
  /* The new award is the newest of its boss's awards, so it moves to the end of that group. */
  const rows = AWARDS.filter((a) => a.status !== "needswinner");
  const old = AWARDS.find((a) => a.status === "needswinner");
  const at = rows.map((a) => a.boss).lastIndexOf(old.boss) + 1;
  rows.splice(at, 0, Object.assign({}, old, { t: PW_TIME, who: done.char || "", how: PW_METHOD[done.method][1], roll: done.roll, status: "corrected" }));
  return rows;
}
function pwRow(a, m, V) {
  if (a.status === "corrected") {
    return `<tr><td class="grey">${a.t}</td><td style="white-space:nowrap"><span class="item-cell">${icon(a.key, "s")}${link(a.key)}</span></td><td>${a.who ? who(a.who) : '<span class="grey">-</span>'}</td>
      <td>${esc(a.how)}</td><td>${a.roll ?? ""}</td><td style="text-align:right;white-space:nowrap"><span class="grey small narrow">Corrected ${PW_TIME}</span> ${btn("Undo", { size: "tiny" })}</td></tr>`;
  }
  if (a.status === "needswinner") {
    const pressed = m.open;
    return `<tr class="hl ${pressed ? "pw-row-open" : ""}"><td class="grey">${a.t}</td><td style="white-space:nowrap"><span class="item-cell">${icon(a.key, "s")}${link(a.key)}</span></td>
      <td>${mode("warn", "Needs a winner")} <span class="hint">${esc(a.note)}</span></td><td></td><td></td>
      <td style="text-align:right"><button type="button" class="btn tiny" aria-expanded="${pressed}" data-goto="${pressed ? "pick-start" : "pick-open"}">Pick winner</button></td></tr>
      ${pressed && V.inRow ? `<tr class="pw-inrow"><td colspan="6">${V.inRow(m)}</td></tr>` : ""}`;
  }
  return awardRow(a, false, false);
}
function pwAwardsBody(m, V) {
  const rows = pwRows(m);
  let html = "", last = "";
  /* In the game the list scrolls inside the window: with the picker open in the row (A), it is
     scrolled down to the row, and the bosses above it are out of view. */
  let shown = rows;
  if (m.open && V.inRow) {
    const from = rows.findIndex((a) => a.boss === "Gehennas");
    const above = [...new Set(rows.slice(0, from).map((a) => a.boss))];
    shown = rows.slice(from);
    html += `<tr><td colspan="6" class="hint" style="text-align:center">▲ ${from} more above (${above.join(", ")}) · scroll</td></tr>`;
  }
  for (const a of shown) {
    if (a.boss !== last) { last = a.boss; const n = rows.filter((x) => x.boss === a.boss).length; html += `<tr class="group"><td colspan="6">${esc(a.boss)} <span class="grey small narrow">· ${n} item${n > 1 ? "s" : ""}</span></td></tr>`; }
    html += pwRow(a, m, V);
  }
  const needs = m.done ? "" : ` · <span class="amber">1 needs a winner</span>`;
  const warn = m.unposted ? `<div class="note-bar warn" style="margin-bottom:8px">${who(PW_POSTED.award && PW_POSTED.award.char || "Hollis Grey")} now has ${link("belt")} on the record, but the correction line couldn't be posted in raid chat. Tell the raid yourself. Type /bf log for why.</div>` : "";
  const summary = `<div class="row hint" style="margin-bottom:6px"><span>12 awards · <span class="amber">1 not confirmed</span>${needs}</span><span class="spacer"></span><span>Sent to the site by the helper: 20:41</span></div>`;
  const head = `<tr><th>Time</th><th>Item</th><th>Winner</th><th>How</th><th>Roll</th><th></th></tr>`;
  return `${warn}${summary}<table class="list"><thead>${head}</thead><tbody>${html}</tbody></table>
    <details style="margin-top:10px"><summary class="gold" style="cursor:pointer;font-size:12px">Practice awards (2) · never sent to the guild site</summary></details>`;
}
function pwChat(m) {
  const L = [];
  if (m.fight) L.push(sysLine("Baron Geddon engaged. Chat is restricted for add-ons until the fight ends."));
  L.push(pwRaidLine(pwUndoLine(m.practice)));
  if (m.done && !m.unposted) L.push(pwRaidLine(pwLine(PW_POSTED.award || { char: "Hollis Grey", method: "SR" }, m.practice)));
  if (m.unposted) L.push(chatLine("sys", `<span style="color:#33ff99">Bureaucracy:</span> ${esc((PW_POSTED.award && PW_POSTED.award.char) || "Hollis Grey")} now has ${link("belt")} on the record, but its raid chat line couldn't be posted. Type /bf log for why.`));
  return chat(L);
}

/* ----- Versions: where the picker opens ----- */
const PW_V = {};
/* A: inside the row, like the pop-up's give-else box. */
PW_V.a = {
  letter: "A", name: "Opens inside the row",
  blurb: "Pick winner opens a box right under the needs-a-winner row, the way the pop-up's Give to someone else opens inside its item's row. The rest of the list stays where it is.",
  win: { x: 330, w: 900 },
  inRow(m) { const p = pwPanel(m); return `<div class="boxed pw-box">${p.body}<div class="btn-row pw-btns">${p.buttons}</div></div>`; },
  overlay() { return ""; },
};
/* B: its own window in the middle of the screen, like the "How was it won?" question. */
PW_V.b = {
  letter: "B", name: "Opens its own window",
  blurb: "Pick winner opens a window in the middle of the screen, like the \"How was it won?\" question after a hand-out from the game's own loot menu. The Awards tab stays behind it.",
  win: { x: 380, w: 840 },
  overlay(m) { const p = pwPanel(m); return notice(`<div class="frame-title-in gold">Pick a winner</div>${p.body}`, p.buttons, { label: "Pick a winner", top: 140, w: 560 }); },
};
/* C: a panel attached to the side of the officers' window. */
PW_V.c = {
  letter: "C", name: "Opens a panel beside the window",
  blurb: "Pick winner opens a narrow panel attached to the right side of the officers' window, like the game's character pane flyouts. The list stays fully visible beside it, with the row marked.",
  win: { x: 330, w: 760 },
  overlay(m) { const p = pwPanel(m); return frame({ id: "pick", title: "Pick a winner", x: 1094, y: 300, w: 330, cls: "pw-side", body: `${p.body}<div class="btn-row pw-btns">${p.buttons}</div>` }); },
};

const PW_GROUPS = [
  ["Pick winner: choosing", ["pick-start", "pick-open", "pick-reserve", "pick-roll", "pick-roll-missing", "pick-db", "pick-again"]],
  ["Pick winner: other cases", ["pick-none", "pick-crowded", "pick-fight", "pick-practice"]],
  ["Pick winner: after", ["pick-done", "pick-unposted"]],
];
const PW_LABELS = {
  "pick-start": "Awards tab: needs a winner", "pick-open": "Picker open, nothing chosen", "pick-reserve": "Another reserve holder chosen",
  "pick-roll": "Someone else, open roll", "pick-roll-missing": "Someone else, roll not valid", "pick-db": "Disenchant/bank chosen", "pick-again": "The previous winner after all",
  "pick-none": "Nobody else reserved it", "pick-crowded": "Many reserve holders", "pick-fight": "Boss fight: posting waits", "pick-practice": "Practice mode",
  "pick-done": "After posting", "pick-unposted": "Recorded, line not posted",
};
let PW_POSTED = {};

function pickScene(state, V) {
  const S = PW_V[V.pwKey];
  const m = pwModel(state);
  const inRow = m.open && S.inRow ? S.inRow : null;
  let out = windowFrame("awards", pwAwardsBody(m, { inRow }), { x: S.win.x, y: 90, w: S.win.w, minH: 420, practice: m.practice });
  if (m.open && !S.inRow) out += S.overlay(m);
  out += pwChat(m);
  out += minimap({ badge: 1 });
  return out;
}

/* Prototype: choices, the member list and typing are local (VIEW.pw survives the re-render that
   data-focus asks for; a state change resets it). Post remembers the posted award for "after". */
document.addEventListener("click", (e) => {
  if (!e.target.closest("#scene")) return;
  const pw = VIEW.pw || (VIEW.pw = {});
  const pick = e.target.closest("[data-pw-pick]");
  if (pick) { const id = pick.dataset.pwPick; if (pw.pick !== id && !pw.noteEdited) delete pw.note; pw.pick = id; pw.menu = id === "__other" && !pw.other && !pwBase(document.documentElement.dataset.state).other; return; }
  if (e.target.closest("[data-pw-menu]")) { pw.menu = !pw.menu; return; }
  const other = e.target.closest("[data-pw-other]");
  if (other) { pw.other = other.dataset.pwOther; pw.menu = false; return; }
  const b = e.target.closest(".btn");
  if (b && b.textContent === "Post correction" && !b.disabled) PW_POSTED = { award: pwAward(pwModel(document.documentElement.dataset.state)).award };
}, true);
document.addEventListener("input", (e) => {
  const pw = VIEW.pw || (VIEW.pw = {});
  if (e.target.matches(".pw-roll")) pw.roll = e.target.value;
  else if (e.target.matches(".pw-note-in")) { pw.note = e.target.value; pw.noteEdited = true; return; }
  else return;
  /* Update the preview and Post in place, so typing keeps its focus. */
  const m = pwModel(document.documentElement.dataset.state);
  const box = e.target.closest(".frame, .pw-box");
  const prev = box.querySelector(".pw-preview"); if (prev) prev.outerHTML = pwPreview(m);
  const row = box.querySelector(".pw-btns") || box.querySelector(".btn-row");
  if (row) row.innerHTML = pwButtons(m);
  e.target.classList.toggle("pw-bad", !!pwAward(m).why);
});
document.addEventListener("keydown", (e) => {
  const t = e.target; if ((e.key !== "Enter" && e.key !== " ") || !t.matches(".pick[data-pw-pick], .mi[data-pw-other]")) return;
  e.preventDefault(); t.click();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && VIEW.pw && VIEW.pw.menu) { const d = document.querySelector("[data-pw-menu]"); if (d) { d.click(); d.focus(); } }
});
document.addEventListener("click", (e) => { if (e.target.closest("#prev, #next")) PW_POSTED = {}; }, true);
document.addEventListener("change", (e) => { if (e.target.id === "state-select") PW_POSTED = {}; }, true);
