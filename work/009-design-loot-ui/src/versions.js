/* The three pop-up layouts. Exactly one is used per built file (VERSION is set by the build). */
"use strict";

const VERSIONS = {};

/* A: list beside the loot window; roll-offs open inside the item's row. Awards listed by time. */
VERSIONS.a = {
  letter: "A", name: "List beside the loot window", groupAwards: false,
  blurb: "Pop-up: one row per item beside the game's loot window; a roll-off opens inside its row. Awards tab: one list by time.",
  popup(m, state) {
    const rows = m.items.map((e, i) => {
      const dbOpen = m.dbMenu === i;
      return `${i ? '<div class="hr-div"></div>' : ""}<div class="row" style="align-items:flex-start;gap:10px;padding:2px 0">
        ${icon(e.key)}
        <div class="col" style="flex:1;gap:2px;min-width:0">
          <div class="row" style="gap:6px">${link(e.key)}${e.copy ? `<span class="hint">· ${esc(e.copy)}</span>` : ""}</div>
          <div class="row" style="gap:6px;flex-wrap:wrap">${modeTag(e)} ${contendersLine(e)}</div>
          ${skippedLines(e)}
          ${e.unavailable ? `<div class="note-bar warn">${esc(e.unavailable)}</div>` : ""}
          ${stagePanel(e)}
        </div>
        <div class="col" style="align-items:flex-end;gap:4px">${e.stage ? "" : primaryButtons(e, m)}${e.stage ? "" : dbButton(e, dbOpen, m)}</div>
      </div>`;
    }).join("");
    const head = `<div class="row" style="margin-bottom:6px">${bossControl(m)}<span class="spacer"></span><span class="hint">${m.items.length} items</span></div>`;
    const body = `${banners(m)}${head}<div class="scroll-list" tabindex="0" aria-label="Items on this corpse">${rows}</div>${statusLine(m)}`;
    const lf = lootframe(m.loot, { page: m.page, title: m.testDrop ? "Test drop" : m.boss });
    const x = state === "practice" ? 60 : 330, y = state === "practice" ? 130 : 150;
    return (state === "practice" ? "" : lf) + frame({ id: "popup", title: popupTitle(m), x, y, w: 560, body });
  },
};

/* B: one item at a time with a queue of the rest; roll-offs inside the card. Awards grouped by boss. */
VERSIONS.b = {
  letter: "B", name: "One item at a time", groupAwards: true,
  blurb: "Pop-up: a larger card for the current item, with the rest queued along the top. Awards tab: grouped by boss.",
  popup(m, state) {
    const f = m.focus ?? 0; const e = m.items[f];
    const queue = m.items.map((x, i) => `<button type="button" class="q-tab" data-focus="${i}" style="position:relative;background:none;border:0;padding:2px;cursor:pointer" aria-label="${esc(ITEMS[x.key].name)}" aria-current="${i === f}">
        <span style="display:block;outline:${i === f ? "2px solid var(--gold)" : "none"};outline-offset:1px">${icon(x.key, "m")}</span>
        <span class="mode ${x.kind === "hr" ? "hr" : x.kind === "sr" ? "sr" : "open"}" style="position:absolute;left:0;right:0;bottom:-10px;font-size:8px;padding:0 1px;text-align:center">${x.kind === "hr" ? "HR" : x.kind === "sr" ? "SR" : "Roll"}</span></button>`).join("");
    const list = e.action === "roll"
      ? `<table class="list"><tbody>${e.contenders.map((n) => `<tr><td>${who(n)}</td><td class="hint" style="text-align:right">${e.stage ? "" : "will roll"}</td></tr>`).join("")}</tbody></table>`
      : e.action === "give" ? `<div class="row" style="font-family:ArialN,sans-serif;font-size:16px">${who(e.winner)} <span class="hint">reserved it${e.kind === "sr" ? " (soft)" : ""}</span></div>`
      : `<div class="hint">${esc(e.note || "")}. Everyone can roll.</div>`;
    const card = `<div class="row" style="gap:12px;align-items:flex-start">${icon(e.key, "l")}
        <div class="col" style="flex:1;gap:4px"><div style="font-size:16px">${link(e.key)}</div>
          <div class="row" style="gap:6px">${modeTag(e)}${e.copy ? `<span class="hint">${esc(e.copy)}</span>` : ""}</div></div></div>
      <div style="margin:8px 0 4px">${e.stage && e.action === "roll" ? "" : list}</div>
      ${skippedLines(e)}
      ${e.unavailable ? `<div class="note-bar warn" style="margin-top:4px">${esc(e.unavailable)}</div>` : ""}
      ${stagePanel(e, { boxed: true })}
      ${e.stage ? "" : `<div class="row" style="margin-top:10px">${primaryButtons(e, m, { big: true })}<span class="spacer"></span>${dbButton(e, m.dbMenu !== undefined, m)}</div>`}`;
    const nav = `<div class="row" style="margin-top:10px">${btn("◀", { size: "tiny", title: "Previous item", focus: (f + m.items.length - 1) % m.items.length })}<span class="hint">Item ${f + 1} of ${m.items.length}</span>${btn("▶", { size: "tiny", title: "Next item", focus: (f + 1) % m.items.length })}<span class="spacer"></span>${bossControl(m)}</div>`;
    const body = `${banners(m)}<div class="row" style="gap:6px;margin-bottom:14px;flex-wrap:wrap">${queue}</div><div class="boxed" style="padding:4px">${card}</div>${nav}${statusLine(m)}`;
    const lf = lootframe(m.loot, { page: m.page, title: m.testDrop ? "Test drop" : m.boss });
    const x = state === "practice" ? 60 : 330, y = state === "practice" ? 130 : 150;
    return (state === "practice" ? "" : lf) + frame({ id: "popup", title: popupTitle(m), x, y, w: 480, body });
  },
};

/* C: labels attached to the game's own loot window; details and roll-offs in a small side window. Awards listed by time. */
VERSIONS.c = {
  letter: "C", name: "Labels on the game's loot window", groupAwards: false,
  blurb: "Pop-up: small labels attached to each slot of the game's own loot window, with roll-offs and details in a small window beside it. Awards tab: one list by time.",
  popup(m, state) {
    const LX = 60, LY = 230;
    const page = m.page || 0, first = page * 4;
    const visible = m.items.slice(first, first + 4);
    const focus = m.focus ?? (m.dbMenu !== undefined ? m.dbMenu : -1);
    const labels = visible.map((e, j) => {
      const i = first + j;
      const top = LY + 74 + 36 * j + 1;
      const what = e.action === "give" ? who(e.winner) : e.action === "roll" ? `<span class="hint">${e.contenders.length} roll</span>` : `<span class="hint">anyone</span>`;
      const act = e.stage ? `<span class="${e.stage === "notconfirmed" || e.stage === "tie" ? "amber" : "gold"} small">${e.stage === "waiting" ? '<span class="spinner"></span>' : e.stage === "notconfirmed" ? "Not confirmed ▸" : e.stage === "tie" ? "Tie ▸" : "Rolling ▸"}</span>`
        : `${e.action === "give" ? btn("Give", { size: "tiny", goto: m.fight || e.unavailable ? "" : "handout-waiting", disabled: m.fight || !!e.unavailable }) : btn("Roll", { size: "tiny", ico: ASSET.dice, goto: m.fight ? "" : "roll-called", disabled: m.fight })}
           <span style="position:relative;display:inline-block">${btn("", { size: "tiny", ico: ASSET.de, goto: m.dbMenu === i ? "popup-typical" : "popup-db", title: "Disenchant/bank: Edric Moss" })}${m.dbMenu === i ? dbMenu() : ""}</span>`;
      const warn = e.unavailable || (e.skipped && e.skipped.length) ? `<button type="button" class="warn-btn amber" data-focus="${i}" title="${esc(e.unavailable || e.skipped.map((s) => s[0] + ": " + s[1]).join("; "))}" aria-label="Details for ${esc(ITEMS[e.key].name)}">⚠</button>` : "";
      return `<div class="tip row" style="left:${LX + 176}px;top:${top}px;width:330px;height:34px;padding:0 6px;gap:6px;z-index:${m.dbMenu === i ? 25 : 6};${focus === i ? "box-shadow:0 0 0 1px var(--gold)" : ""}">
        ${mode(e.kind === "hr" ? "hr" : e.kind === "sr" ? "sr" : "open", e.kind === "hr" ? "HR" : e.kind === "sr" ? "SR" : "Roll")}<span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${what}</span>${warn}${act}</div>`;
    }).join("");
    const more = m.items.length > 4 ? `<div class="hint" style="position:absolute;left:${LX + 190}px;top:${LY + 226}px;z-index:6">${page === 0 ? `${m.items.length - 4} more on page 2 of the loot window: labels follow the page` : `Page 2 of the loot window: items 5 to ${m.items.length}`}</div>` : "";
    const strip = `<div class="tip" style="left:${LX}px;top:${LY - 66}px;width:506px;z-index:6">
        <div class="row">${m.practice ? mode("practice", "Practice") : ""}${bossControl(m)}<span class="spacer"></span><span class="hint" style="font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0">${m.noReserves ? "Reserves: none loaded" : esc(STATUS_LINE)}</span></div></div>`;
    const bannerHTML = banners(m);
    const bannerBox = bannerHTML ? `<div style="position:absolute;left:${LX}px;top:${LY + 270}px;width:506px;z-index:6">${bannerHTML}</div>` : "";
    /* Side window: shows details for the focused item, roll-offs and hand-out problems */
    let side = "";
    const fe = focus >= 0 && focus < m.items.length && m.dbMenu === undefined ? m.items[focus] : null;
    if (fe) {
      const body = `<div class="row" style="gap:8px">${icon(fe.key, "m")}<div class="col" style="gap:2px">${link(fe.key)}<div class="row" style="gap:6px">${modeTag(fe)}</div></div></div>
        ${skippedLines(fe)}${stagePanel(fe, { boxed: false })}`;
      side = frame({ id: "detail", title: fe.stage === "waiting" || fe.stage === "notconfirmed" || fe.stage === "giveelse" ? "Hand-out" : fe.stage ? "Roll-off" : "Item details", x: 620, y: 200, w: 400, body });
    } else if (state === "popup-crowded" || state === "popup-page2" || state === "popup-unavailable") {
      const withSkips = m.items.filter((e) => (e.skipped && e.skipped.length) || e.unavailable);
      side = frame({ id: "detail", title: "Skipped holders", x: 620, y: 200, w: 400, body: withSkips.map((e) => `<div class="row" style="gap:6px;margin:4px 0">${icon(e.key, "s")}${link(e.key)}</div>${skippedLines(e)}${e.unavailable ? `<div class="note-bar warn">${esc(e.unavailable)}</div>` : ""}`).join("") + `<div class="hint" style="margin-top:6px">Hover or click ⚠ on a label to see one item.</div>` });
    }
    return lootframe(m.loot, { x: LX, y: LY, page, title: m.testDrop ? "Test drop" : m.boss }) + strip + labels + more + bannerBox + side;
  },
};

/* D: Robert's picks combined: A's pop-up with B's Awards grouped by boss. */
VERSIONS.d = Object.assign({}, VERSIONS.a, {
  letter: "D", name: "A's pop-up, Awards grouped by boss", groupAwards: true,
  blurb: "Pop-up: one row per item beside the game's loot window; a roll-off opens inside its row. Awards tab: grouped by boss.",
});
