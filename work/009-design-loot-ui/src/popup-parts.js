/* Pop-up building blocks shared by every version: same wording and behaviour, different layout. */
"use strict";

const RAID_MEMBERS = Object.keys(PEOPLE).sort();

function modeTag(e) {
  const k = e.kind === "hr" ? "hr" : e.kind === "sr" ? "sr" : e.kind === "db" ? "db" : "open";
  return mode(k, e.label);
}
function contendersLine(e) {
  if (e.action === "openroll") return `<span class="hint">${esc(e.note || "")}${e.note ? " · " : ""}everyone can roll</span>`;
  if (e.action === "roll") return `<span class="narrow">${e.contenders.map((n) => who(n)).join(", ")}</span>${e.note ? ` <span class="hint">· ${esc(e.note)}</span>` : ""}`;
  return `<span class="narrow">${who(e.winner === "Unknown" ? "Unknown" : e.winner)}</span>`;
}
function skippedLines(e) {
  if (!e.skipped || !e.skipped.length) return "";
  return `<div class="hint" style="font-size:12px">Skipped: ${e.skipped.map(([n, why]) => `${who(n, { absent: true })} <span class="grey">(${esc(why)})</span>`).join("; ")}</div>`;
}
function dbButton(e, open, m) {
  const pick = m && m.dbPick !== undefined ? m.dbPick : "Edric Moss";
  return `<span style="position:relative;display:inline-block">${btn(`D/B: ${pick ? esc(pick.split(" ")[0]) : "choose"} ▾`, { size: "tiny", ico: ASSET.de, goto: open ? "popup-typical" : "popup-db", title: "Disenchant/bank: give to the chosen character" })}
    ${open ? dbMenu() : ""}</span>`;
}
function dbMenu() {
  const items = RAID_MEMBERS.slice(0, 12).map((n) => `<div class="mi ${n === "Edric Moss" ? "sel" : ""}"><span class="chk">${n === "Edric Moss" ? "✓" : ""}</span>${who(n)}</div>`).join("");
  return `<div class="tip menu" style="left:0;top:24px;width:210px"><div class="menu-title">Disenchant/bank: give to</div>${items}
    <div class="hint" style="margin-top:3px">▼ 13 more · scroll</div><div class="hint" style="margin-top:3px">Remembered for this raid.</div></div>`;
}
function primaryButtons(e, m, opts = {}) {
  const dis = m.fight ? { disabled: true, title: "Chat is locked until the fight ends" } : {};
  const big = opts.big ? "big" : "";
  if (e.done) return `<span class="green narrow">✓ Given to ${who(e.done)}</span>`;
  if (e.unavailable) return btn(`Give to Unknown`, { disabled: true, size: big });
  if (e.action === "give") return btn(`Give to ${esc(e.winner)}`, { size: big, goto: m.fight ? "" : "handout-waiting", ...dis });
  if (e.action === "roll") return btn(`Call roll (${e.contenders.length})`, { size: big, ico: ASSET.dice, goto: m.fight ? "" : "roll-called", ...dis });
  return btn("Call open roll", { size: big, ico: ASSET.dice, goto: m.fight ? "" : "roll-called", ...dis });
}
/* Roll-off panel: the content shown once a roll is called */
function rollPanel(e, o = {}) {
  if (e.stage === "rolling") {
    const top = e.rolls[0];
    return `<div class="${o.boxed === false ? "" : "boxed"}" style="margin-top:6px">
      <div class="row" style="margin-bottom:3px"><span class="gold small">Rolls (hard reserve holders only)</span><span class="spacer"></span><span class="hint">3 of 4 rolled</span></div>
      <table class="list"><tbody>
        ${e.rolls.map(([n, r], i) => `<tr ${i === 0 ? 'class="hl"' : ""}><td style="width:18px">${i === 0 ? '<span class="gold">●</span>' : '<span class="grey">○</span>'}</td><td>${who(n)}</td><td style="text-align:right" class="${i === 0 ? "gold" : ""}">${r}</td></tr>`).join("")}
        ${e.waiting.map((n) => `<tr><td></td><td>${who(n)}</td><td style="text-align:right" class="hint">waiting</td></tr>`).join("")}
        ${e.ignored.map(([n, r, why]) => `<tr><td></td><td class="grey">${esc(n)} <span class="small">(${esc(why)})</span></td><td style="text-align:right" class="grey"><s>${r}</s></td></tr>`).join("")}
      </tbody></table>
      <div class="btn-row" style="margin-top:6px">${btn(`Give to ${esc(top[0])} (${top[1]})`, { goto: "handout-waiting" })}<span class="hint">or click another name</span></div></div>`;
  }
  if (e.stage === "tie") {
    return `<div class="${o.boxed === false ? "" : "boxed"}" style="margin-top:6px">
      <div class="note-bar warn" style="margin-bottom:4px">Tie at 87: ${e.tie.map((n) => who(n)).join(" and ")}</div>
      <table class="list"><tbody>${e.rolls.map(([n, r]) => `<tr ${e.tie.includes(n) ? 'class="hl"' : ""}><td>${who(n)}</td><td style="text-align:right" class="${e.tie.includes(n) ? "amber" : ""}">${r}</td></tr>`).join("")}</tbody></table>
      <div class="btn-row" style="margin-top:6px">${btn("Re-roll the tie", { ico: ASSET.dice, goto: "roll-called" })}<span class="hint">Posts: Tie for ${link("robe")}: Mirel Stone and Tovin Hale, roll again</span></div></div>`;
  }
  if (e.stage === "hidden") {
    return `<div class="${o.boxed === false ? "" : "boxed"}" style="margin-top:6px">
      <div class="note-bar warn" style="margin-bottom:6px">The game is hiding rolls from add-ons right now. Watch chat, then click the winner.</div>
      <div class="btn-row">${e.contenders.map((n) => btn(esc(n), { size: "tiny", goto: "handout-waiting" })).join("")}</div>
      <div class="row" style="margin-top:6px"><span class="hint">Their roll (optional):</span><input class="input" style="width:60px" aria-label="Winning roll"></div></div>`;
  }
  return "";
}
/* Hand-out stages after the award click */
function handoutPanel(e, o = {}) {
  if (e.stage === "waiting") return `<div class="${o.boxed === false ? "" : "boxed"}" style="margin-top:6px"><span class="spinner"></span> <span class="gold">Handing out to ${who(e.winner)}…</span>
    <div class="hint">Announced in raid chat. Waiting for the game to confirm (a few seconds).</div></div>`;
  if (e.stage === "notconfirmed") return `<div class="${o.boxed === false ? "" : "boxed"}" style="margin-top:6px">
    <div class="note-bar warn" style="margin-bottom:6px">The game didn't confirm that ${who(e.winner)} got it. They may be too far away, or their bags are full.</div>
    <div class="btn-row">${btn("Try again", { goto: "handout-waiting", title: "Hand out again, no new announcement" })}${btn("Give to someone else", { goto: "give-else" })}${btn("Not handed out", { goto: "popup-typical" })}</div>
    <div class="hint" style="margin-top:4px">Try again posts nothing. The other two post a correction line. If you close this, it waits in the Awards tab as "not confirmed".</div></div>`;
  if (e.stage === "giveelse") {
    const list = ["Doran Vale", "Mirel Stone", "Tovin Hale", "Edric Moss"];
    return `<div class="${o.boxed === false ? "" : "boxed"}" style="margin-top:6px">
      <div class="gold small" style="margin-bottom:4px">Give ${link("choker")} to someone else</div>
      <table class="list"><tbody>
        <tr><td>${who("Doran Vale")}</td><td>${mode("sr", "Soft reserve")}</td><td style="text-align:right">${btn("Give", { size: "tiny", goto: "handout-waiting" })}</td></tr>
        <tr><td>${who("Mirel Stone", { absent: true })}</td><td class="grey small">not in raid</td><td></td></tr>
        <tr><td>Open roll</td><td class="hint">everyone can roll</td><td style="text-align:right">${btn("Call open roll", { size: "tiny", goto: "roll-called" })}</td></tr>
        <tr><td>Disenchant/bank</td><td>${who("Edric Moss")}</td><td style="text-align:right">${btn("Give", { size: "tiny", goto: "handout-waiting" })}</td></tr>
      </tbody></table>
      <div class="hint" style="margin-top:4px">Posts: Correction: ${link("choker")} was not handed to Ashla Brightwater, then the new award line.</div></div>`;
  }
  return "";
}
function stagePanel(e, o) { return rollPanel(e, o) || handoutPanel(e, o); }

function bossControl(m) {
  const menu = m.bossMenu ? `<div class="tip menu" style="left:44px;top:22px;width:220px"><div class="menu-title">Which boss dropped this?</div>
      ${["Trash", "Lucifron", "Magmadar", "Gehennas"].map((b) => `<div class="mi ${b === "Lucifron" ? "sel" : ""}"><span class="chk">${b === "Trash" ? "✓" : ""}</span><span class="white">${b}</span>${b === "Lucifron" ? '<span class="hint">· killed 20:01</span>' : ""}</div>`).join("")}</div>` : "";
  return `<span style="position:relative" class="row"><span class="gold small">Boss:</span><button type="button" class="dd" data-goto="${m.bossMenu ? "popup-typical" : "popup-boss"}">${esc(m.boss)}</button>${menu}</span>`;
}
function banners(m) {
  let s = "";
  if (m.practice) s += `<div class="note-bar" style="margin-bottom:6px">${mode("practice", "Practice")} Test drop: no corpse, reserves are made up, nothing is handed out or sent to the site.</div>`;
  if (m.noReserves) s += `<div class="note-bar warn" style="margin-bottom:6px">No reserves loaded, so every item is an open roll. <button type="button" class="linkish" data-goto="sync-empty">Load reserves</button></div>`;
  if (m.fight) s += `<div class="note-bar warn" style="margin-bottom:6px">Boss fight in progress. The game locks chat for add-ons, so awards wait until it ends.</div>`;
  if (m.bossNote) s += `<div class="note-bar" style="margin-bottom:6px">${esc(m.bossNote)}</div>`;
  return s;
}
function statusLine(m) {
  return `<div class="hint" style="font-size:12px;margin-top:6px">${m.noReserves ? "Reserves: none loaded" : esc(STATUS_LINE)}${m.practice ? " · <span class='gold'>practice</span>" : ""}</div>`;
}
function popupTitle(m) { return `${m.practice ? "[Practice] " : ""}Loot · ${esc(m.boss)}`; }
