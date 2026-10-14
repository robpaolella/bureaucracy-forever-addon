/* ---------- Revision 2: the raid question and the Sync tab (design #44) ----------
   Sample data only. Shared content; each version (SYNC_V) decides layout and how the question is asked. */
const ME = "Konvett Konvett";            /* the officer at this screen, the loot master */
const OTHER = "Seraphine Ashdown";        /* another officer, for the follower view */
const RAIDS = {
  mc: { name: "Molten Core", day: "Thu 10 Dec", when: "Under way since 19:30", live: true, inst: 409, zone: "Molten Core", players: 38, reserves: 61, awards: 12, undo: 1, src: "helper" },
  ony: { name: "Onyxia's Lair", day: "Thu 10 Dec", when: "Starts 22:00", inst: 249, zone: "Onyxia's Lair", players: 40, reserves: 14, awards: 0, src: "helper" },
  mc2: { name: "Molten Core: second team", day: "Thu 10 Dec", when: "Under way since 19:45", live: true, inst: 409, zone: "Molten Core", players: 22, reserves: 30, awards: 0, src: "helper" },
  zg: { name: "Zul'Gurub alt run (custom raid with a very long name)", day: "Thu 10 Dec", when: "Starts 21:00", inst: null, players: 12, reserves: 9, awards: 0, src: "helper" },
  bwl: { name: "Blackwing Lair", day: "Wed 9 Dec", when: "Ended 23:10 yesterday", inst: 469, zone: "Blackwing Lair", players: 39, reserves: 58, awards: 3, src: "pasted", pasted: "19:42" },
};
const rname = (id) => `${RAIDS[id].name}, ${RAIDS[id].day}`;

/* Per state: which raids are loaded, which is selected, by whom, where the officer is */
function syncModel(state) {
  const m = { list: ["mc", "ony"], sel: "mc", by: ME, at: "19:31", zone: "Molten Core", inst: 409, helper: true, viewer: ME, noraid: 0 };
  switch (state) {
    case "ask-guild": case "ask-raid": case "ask-fallback": Object.assign(m, { sel: null, by: null }); break;
    case "ask-overlap": Object.assign(m, { list: ["mc", "mc2", "ony"], sel: null, by: null }); break;
    case "ask-nomatch": Object.assign(m, { sel: null, by: null, zone: "Zul'Gurub", inst: 309 }); break;
    case "ask-again": Object.assign(m, { zone: "Onyxia's Lair", inst: 249 }); break;
    case "sync-follower": m.viewer = OTHER; break;
    case "sync-off": Object.assign(m, { sel: "off" }); break;
    case "sync-undecided": Object.assign(m, { sel: null, by: null, noraid: 2 }); break;
    case "sync-crowded": Object.assign(m, { list: ["mc", "mc2", "ony", "zg", "bwl"] }); break;
    case "sync-gone": Object.assign(m, { list: ["ony"], sel: null, by: null, gone: "mc" }); break;
    case "sync-empty": Object.assign(m, { list: [], sel: null, by: null, helper: false, zone: null, inst: null }); break;
    case "sync-pasted": case "sync-remove": case "sync-refused":
      RAIDS.mcp = Object.assign({}, RAIDS.mc, { src: "pasted", pasted: "19:42" });
      Object.assign(m, { list: ["mcp"], sel: "mcp", helper: false, pastedSel: true }); break;
    case "sync-noraid": case "sync-discard": Object.assign(m, { noraid: 3 }); break;
  }
  return m;
}

/* ----- Shared pieces ----- */
function radio(on, label, o = {}) {
  return `<span class="rb ${on ? "on" : ""}" role="radio" aria-checked="${on}" ${o.disabled ? 'aria-disabled="true"' : ""}></span>${label}`;
}
function raidFacts(id, o = {}) {
  const r = RAIDS[id];
  const inst = r.inst ? `Instance ${r.inst}` : `<span class="amber">No instance number</span>`;
  const src = r.src === "pasted" ? `Pasted ${r.pasted}` : "From the helper";
  return o.short ? `${esc(r.when)} · ${r.players} players` : `${esc(r.when)} · ${inst} · ${r.players} players · ${r.reserves} reserves · ${src}`;
}
function chosenLine(m) {
  if (m.sel === "off") return m.by === m.viewer ? `You chose this at ${m.at}.` : `${who(m.by)} (loot master) chose this at ${m.at}.`;
  if (!m.by) return "";
  const by = m.by === m.viewer ? "you" : `${who(m.by)} (loot master)`;
  return m.pastedSel ? `Chosen when you pasted its reserves at 19:50.` : `Chosen by ${by} at ${m.at}. Awards from this group go to this raid.`;
}
function whereLine(m) {
  if (!m.inst) return `<span class="hint">You're not in an instance.</span>`;
  return `<span class="hint">You're in ${esc(m.zone)} (instance ${m.inst}).</span>`;
}
function statusBar(m) {
  if (m.sel === "off") return `<div class="note-bar"><b>Not a guild run.</b> The add-on is off for this group: no loot pop-up, no chat lines, nothing recorded. It turns back on when you leave the group.<div class="row hint" style="margin-top:4px">${chosenLine(m)}<span class="spacer"></span>${btn("It's a guild run", { size: "tiny", goto: "ask-raid" })}</div></div>`;
  if (m.gone) return `<div class="note-bar warn"><b>No raid chosen.</b> ${esc(rname(m.gone))} has left the helper's list. Awards are held as "no raid" until a raid is chosen.</div>`;
  if (!m.list.length) return `<div class="note-bar warn"><b>No raids loaded.</b> The pop-up still works, but every item is an open roll.</div>`;
  if (!m.sel) return `<div class="note-bar warn"><b>No raid chosen yet.</b> Awards are held as "no raid" until you choose one. ${btn("Choose the raid", { size: "tiny", goto: "ask-raid" })}</div>`;
  const r = RAIDS[m.sel];
  return `<div class="note-bar good"><b>${esc(rname(m.sel))}</b> · ${r.players} players · ${r.reserves} reserves · ${r.awards} awards<div class="hint" style="margin-top:2px;color:#cfe9c9">${chosenLine(m)}</div></div>`;
}
function helperLine(m) {
  return m.helper
    ? `<div class="row hint"><img class="dot" alt="" src="${ASSET.dotGreen}"> Desktop helper in use: raid events read at 19:28 (they update at login or /reload), and awards go to the site live.</div>`
    : `<div class="row hint"><img class="dot" alt="" src="${ASSET.dotGray}"> Desktop helper not running: paste reserves in and copy awards out below.</div>`;
}
function pasteBox(m, state) {
  const refused = state === "sync-refused";
  return `<div class="gold" style="margin:2px 0 4px">Reserves in</div>
    <div class="hint" style="margin-bottom:4px">On the guild site, open the raid and choose <b class="white">Copy reserves</b>. Paste it here with Ctrl+V (Cmd+V on Mac). Pasting chooses that raid for the group.</div>
    <textarea class="input" rows="2" aria-label="Paste reserves" placeholder="Paste the reserves text here">${refused ? "BFSNAP2:1/1:{formatVersion=2,raid=&quot;cm9xr2k4a0001&quot;..." : ""}</textarea>
    <div class="row" style="margin-top:6px">${btn("Load", { goto: m.list.length ? "" : "sync-pasted" })}</div>
    ${refused ? `<div class="note-bar bad" style="margin-top:8px">This text needs a newer version of the add-on (you have 1.2.1). Nothing was loaded; your raids are unchanged.</div>
      <div class="row" style="margin-top:6px"><span class="hint">Download link:</span><input class="input selected-text" style="flex:1" readonly aria-label="Download link" value="https://github.com/robpaolella/bureaucracy-forever-addon/releases/latest"></div>
      <div class="hint" style="margin-top:4px">Press Ctrl+C to copy the link, open it in your browser, replace the add-on folder, then /reload.</div>` : ""}`;
}
function raidPicker(m, label) {
  const id = m.sel && m.sel !== "off" ? m.sel : m.list.find((x) => RAIDS[x].awards) || m.list[0];
  return `<span class="hint">${label}</span> <button type="button" class="dd" aria-haspopup="listbox">${id ? esc(rname(id)) : "No raids"}</button>`;
}
function awardsOut(m, state) {
  const id = m.sel && m.sel !== "off" ? m.sel : null;
  const has = id && RAIDS[id].awards;
  const selected = state === "sync-pasted";
  return `<div class="gold" style="margin-bottom:4px">Awards out</div>
    <div class="hint" style="margin-bottom:6px">${m.helper ? "Not needed while the desktop helper runs. " : ""}Paste the text into <b class="white">Import awards</b> on the raid's page on the guild site.</div>
    ${selected ? `<div class="hint" style="margin-bottom:4px">The text is selected: press Ctrl+C (Cmd+C on Mac).</div><textarea class="input selected-text" rows="2" aria-label="Awards to copy" readonly>BFOUT1;cm9xr2k4a0001;PA0001;production
A;19-4410;lb_lucifron;19837;Ashla Brightwater;u_ana;HR;;;Konvett Konvett;1792001520;...</textarea><div style="height:6px"></div>` : ""}
    <div class="row">${m.list.length ? raidPicker(m, "Raid:") : ""}${btn("Copy awards", { disabled: !has, goto: has ? "sync-pasted" : "" })}<span class="hint">${has ? "12 awards, 1 undo. Practice awards are never included." : "Nothing to copy yet."}</span></div>`;
}
function noraidBlock(m) {
  if (!m.noraid) return "";
  const rows = [["19:58", "Trash", "core", "Quill Ashby", 82], ["20:02", "Lucifron", "choker", "Ashla Brightwater", 71], ["20:02", "Lucifron", "gloves", "Doran Vale", 64]].slice(0, m.noraid);
  return `<div class="note-bar warn" style="margin-bottom:6px"><b>${m.noraid} awards aren't linked to a raid.</b> They were made while no raid was chosen, so they can't be sent to the site yet.</div>
    <table class="list"><tbody>${rows.map(([t, b, k, w, r]) => `<tr><td class="grey">${t}</td><td>${b}</td><td><span class="item-cell">${icon(k, "s")}${link(k)}</span></td><td>${who(w)}</td><td>Open roll</td><td>${r}</td></tr>`).join("")}</tbody></table>
    <div class="row" style="margin:8px 0 4px">${m.list.length ? raidPicker(m, "Attach to:") : ""}${btn("Attach", { disabled: !m.list.length })}${btn("Discard", { goto: "sync-discard" })}<span class="spacer"></span></div>
    <div class="hint" style="margin-bottom:8px">Methods stay as recorded; fix any on the site afterwards. Discard if they were from a run that wasn't a guild run.</div>`;
}

/* ----- The questions ----- */
function askList(m, pre, o = {}) {
  const rows = m.list.map((id) => {
    const r = RAIDS[id]; const on = id === pre;
    const match = r.inst && r.inst === m.inst && (r.live || r.when.startsWith("Starts"));
    return `<label class="pick ${on ? "on" : ""}" tabindex="0">${radio(on, `<span class="col" style="gap:0;text-align:left"><span class="white">${esc(rname(id))}${match ? ` <span class="mode ok">Matches</span>` : ""}</span><span class="hint" style="font-size:12px">${raidFacts(id, { short: true })}</span></span>`)}</label>`;
  }).join("");
  const off = o.withOff ? `<div class="hr-div"></div><label class="pick" tabindex="0" data-off="1">${radio(false, `<span class="col" style="gap:0;text-align:left"><span class="white">No, not a guild run</span><span class="hint" style="font-size:12px">The add-on stays off until you leave the group</span></span>`)}</label>` : "";
  return `<div class="pick-list" role="radiogroup" aria-label="Raid events">${rows}${off}</div>`;
}
function askContent(state, m, flow) {
  /* returns { title, body, buttons } for one step of the question */
  const where = `You've entered <b class="white">${esc(m.zone)}</b> with a raid group.`;
  const fallback = state === "ask-fallback" ? `<div class="note-bar warn" style="margin:6px 0;text-align:left">You're asked because master loot is off and you lead the raid. Turn master loot on to hand out items with the pop-up.</div>` : "";
  if (state === "ask-again") return { title: "Bureaucracy Forever", body: `<p>You've entered <b class="white">${esc(m.zone)}</b>. Switch the raid to <b class="white">${esc(rname("ony"))}</b>?</p><p class="hint">Your 12 Molten Core awards stay with that raid and are still sent to the site.</p>`,
    buttons: btn("Switch", { goto: "sync-chosen" }) + btn("Keep Molten Core", { goto: "sync-chosen" }) + btn("Not a guild run", { goto: "sync-off" }) };
  if (flow === "one") {
    const pre = state === "ask-overlap" || state === "ask-nomatch" ? null : "mc";
    const lead = state === "ask-overlap" ? `<p>${where} Two raid events for Molten Core are under way. Which one is this?</p>`
      : state === "ask-nomatch" ? `<p>${where}</p><p class="hint">No raid event is set for Zul'Gurub (instance 309). If this is a custom raid, an officer can enter 309 as its In-game instance number on the guild site.</p>`
      : `<p>${where} If it's a guild run, pick its raid event. If not, choose the last option.</p>`;
    return { title: "Is this a guild run?", body: `${lead}${fallback}${askList(m, pre, { withOff: true })}`,
      buttons: btn("Start", { disabled: !pre, goto: "sync-chosen" }) + btn("Later", { goto: "sync-undecided" }) };
  }
  if (state === "ask-guild" || state === "ask-fallback") return { title: "Is this a guild run?", body: `<p>${where} Is this a guild run?</p>${fallback}<p class="hint">If not, the add-on stays off until you leave the group: no loot pop-up, nothing recorded.</p>`,
    buttons: btn("Guild run", { goto: "ask-raid" }) + btn("Not a guild run", { goto: "sync-off" }) + btn("Later", { goto: "sync-undecided" }) };
  const pre = state === "ask-raid" ? "mc" : null;
  const lead = state === "ask-overlap" ? `<p>Two raid events for Molten Core are under way. Which one is this?</p>`
    : state === "ask-nomatch" ? `<p>No raid event is set for <b class="white">Zul'Gurub</b> (instance 309). Which one is this?</p><p class="hint">If it's a custom raid, an officer can enter 309 as its In-game instance number on the guild site.</p>`
    : `<p>Which raid event is this?</p>`;
  return { title: "Which raid event?", body: `${lead}${askList(m, pre)}`,
    buttons: btn("Start", { disabled: !pre, goto: "sync-chosen" }) + btn("Back", { goto: "ask-guild" }) + btn("Later", { goto: "sync-undecided" }) };
}
function askDialog(state, m, V) {
  const c = askContent(state, m, V.flow);
  if (V.askAt === "corner") {
    return frame({ id: "ask", title: c.title, x: 1050, y: 236, w: 360, close: false,
      body: `<div class="ask-corner">${c.body}<div class="btn-row">${c.buttons}</div></div>` });
  }
  return notice(`<div class="gold" style="font-size:14px;margin-bottom:2px">${esc(c.title)}</div>${c.body}`, c.buttons, { label: c.title, top: 200, w: 480 });
}

/* Confirmation dialogs (same in every version) */
function syncDialog(state) {
  switch (state) {
    case "sync-switch": return notice(`<p>Switch the raid to <b class="white">${esc(rname("ony"))}</b>?</p><p class="hint">You have 12 awards for Molten Core. They stay with that raid and are still sent to the site. Every officer in the group switches too.</p>`,
      btn("Switch", { goto: "sync-chosen" }) + btn("Keep Molten Core", { goto: "sync-chosen" }), { top: 260, label: "Switch raid" });
    case "sync-gone": return notice(`<p><b class="white">${esc(rname("mc"))}</b> has left the helper's list: it was cancelled or has ended.</p><p class="hint">Its 12 awards are kept and still sent to the site. You'll be asked which raid it is when you next enter a raid instance.</p>`,
      btn("Choose a raid now", { goto: "ask-raid" }) + btn("OK", { goto: "__close" }), { top: 260, label: "Raid left the list" });
    case "sync-remove": return notice(`<p>Remove <b class="white">${esc(rname("mc"))}</b>?</p><p class="hint">Its 12 awards stay saved and can still be copied.</p>`,
      btn("Remove", { goto: "sync-empty" }) + btn("Cancel", { goto: "sync-pasted" }), { top: 260, label: "Remove raid" });
    case "sync-discard": return notice(`<p>Discard <b class="white">3 awards</b> that aren't linked to a raid?</p><p class="hint">They were never sent to the site. This can't be undone.</p>`,
      btn("Discard", { goto: "sync-chosen" }) + btn("Cancel", { goto: "sync-noraid" }), { top: 260, label: "Discard awards" });
  }
  return "";
}

/* ----- Versions: Sync tab layout ----- */
const SYNC_V = {};
/* A: one column. The raid list is a table with a choice per row, then reserves in and awards out. */
SYNC_V.a = {
  letter: "A", name: "Raid list on the tab, two-step question", flow: "two", askAt: "center",
  blurb: "Sync tab: one column with the raid list as a table (a choice per row, Not a guild run as the last row), then reserves in and awards out. Question: two steps in the middle of the screen (guild run? then which raid event).",
  body(m, state) {
    const rows = m.list.map((id) => {
      const r = RAIDS[id]; const on = id === m.sel;
      const go = on ? "" : RAIDS[m.sel] && RAIDS[m.sel].awards ? "sync-switch" : "sync-chosen";
      return `<tr class="${on ? "hl-sel" : ""} pickrow" ${go ? `data-goto="${go}" tabindex="0"` : ""}><td style="width:26px">${radio(on, "")}</td><td><span class="white">${esc(r.name)}</span> <span class="grey small">${esc(r.day)}</span></td><td style="white-space:nowrap">${esc(r.when)}</td>
        <td>${r.inst ? r.inst : '<span class="amber">None</span>'}</td><td>${r.players} · ${r.reserves}</td><td>${r.awards || '<span class="grey">-</span>'}</td>
        <td style="text-align:right">${r.src === "pasted" ? `<span class="grey small">Pasted ${r.pasted}</span> ${btn("Remove", { size: "tiny", goto: "sync-remove" })}` : ""}</td></tr>`;
    }).join("");
    const off = m.list.length ? `<tr class="${m.sel === "off" ? "hl-sel" : ""} pickrow" data-goto="sync-off" tabindex="0"><td>${radio(m.sel === "off", "")}</td><td colspan="6"><span class="white">Not a guild run</span> <span class="hint">· the add-on stays off until you leave the group</span></td></tr>` : "";
    const table = m.list.length ? `<table class="list" style="margin-top:6px"><thead><tr><th></th><th>Raid event</th><th>When</th><th>Instance</th><th>Players · reserves</th><th>Awards</th><th></th></tr></thead><tbody>${rows}${off}</tbody></table>
      <div class="row" style="margin-top:4px">${whereLine(m)}<span class="spacer"></span><span class="hint">Choosing another raid changes it for every officer in the group.</span></div>` : "";
    return `${statusBar(m)}<div style="height:6px"></div>${noraidBlock(m)}<div class="gold" style="margin:4px 0 0">Raid events</div>${table}
      <div style="margin-top:6px">${helperLine(m)}</div><div class="hr-div" style="margin:10px 0 6px"></div>
      ${m.helper && state !== "sync-crowded" ? `<div class="row"><span class="gold">Reserves in</span><span class="hint">Only needed without the helper.</span><span class="spacer"></span>${btn("Paste reserves", { size: "tiny", goto: "sync-empty", title: "Opens the paste box (prototype: shown as the empty state)" })}</div>` : pasteBox(m, state)}
      <div class="hr-div" style="margin:10px 0 6px"></div>${awardsOut(m, state)}`;
  },
};
/* B: list and details side by side. Pick a raid on the left; the right shows it and its actions. */
SYNC_V.b = {
  letter: "B", name: "Raid list beside the details, one-step question", flow: "one", askAt: "center",
  blurb: "Sync tab: raid events listed on the left (with Not a guild run and Paste reserves at the bottom); the right shows the chosen raid and its actions. Question: one step in the middle of the screen (the raid list with No, not a guild run as the last choice).",
  body(m, state) {
    const pasteMode = !m.list.length || state === "sync-refused";
    const item = (id) => {
      const r = RAIDS[id]; const on = id === m.sel;
      const go = on ? "" : RAIDS[m.sel] && RAIDS[m.sel].awards ? "sync-switch" : "sync-chosen";
      return `<button type="button" class="side-item ${on ? "on" : ""}" aria-pressed="${on}" ${go ? `data-goto="${go}"` : ""}><span class="white">${esc(r.name)}</span>${on ? ` <span class="mode ok">${m.pastedSel ? "Pasted" : "In use"}</span>` : ""}<span class="hint" style="display:block;font-size:12px">${esc(r.day)} · ${esc(r.when)}${r.inst ? "" : ' · <span class="amber">no instance number</span>'}</span></button>`;
    };
    const left = `<div class="side-list"><div class="gold small" style="margin:0 0 4px 4px">Raid events</div>${m.list.map(item).join("") || '<div class="hint" style="padding:6px">None loaded.</div>'}
      <div class="hr-div"></div>
      <button type="button" class="side-item ${m.sel === "off" ? "on" : ""}" aria-pressed="${m.sel === "off"}" data-goto="sync-off"><span class="white">Not a guild run</span><span class="hint" style="display:block;font-size:12px">Turns the add-on off for this group</span></button>
      <button type="button" class="side-item ${pasteMode ? "on" : ""}" data-goto="sync-empty" title="Opens the paste box (prototype: shown as the empty state)"><span class="white">Paste reserves…</span><span class="hint" style="display:block;font-size:12px">Without the helper</span></button>
      <div style="margin-top:8px">${helperLine(m)}</div></div>`;
    let right;
    if (pasteMode) right = `${statusBar(m)}<div style="height:8px"></div>${pasteBox(m, state)}<div class="hr-div" style="margin:12px 0 6px"></div>${awardsOut(m, state)}`;
    else if (m.sel === "off" || !m.sel) right = `${statusBar(m)}<div style="height:8px"></div>${noraidBlock(m)}${whereLine(m)}`;
    else {
      const r = RAIDS[m.sel];
      right = `<div class="gold" style="font-size:16px">${esc(rname(m.sel))}</div>
        <div class="hint" style="margin:2px 0 6px">${raidFacts(m.sel)}</div>
        <div class="note-bar good">${chosenLine(m)}</div>
        <div class="row" style="margin:6px 0">${whereLine(m)}</div>
        <div class="row hint" style="gap:18px;margin:4px 0 8px"><span><b class="white">${r.players}</b> players</span><span><b class="white">${r.reserves}</b> reserves</span><span><b class="white">${r.awards}</b> awards</span></div>
        ${noraidBlock(m)}
        <div class="hr-div" style="margin:8px 0 6px"></div>${awardsOut(Object.assign({}, m, { list: [] }), state)}
        ${r.src === "pasted" ? `<div class="row" style="margin-top:10px"><span class="hint">Pasted ${r.pasted}.</span>${btn("Remove", { size: "tiny", goto: "sync-remove" })}</div>` : ""}
        <div class="hint" style="margin-top:10px">Choosing another raid on the left changes it for every officer in the group.</div>`;
    }
    return `<div class="split"><div>${left}</div><div class="split-r">${right}</div></div>`;
  },
};
/* C: compact. One line says the raid, with a dropdown to change it; paste sits behind a button. */
SYNC_V.c = {
  letter: "C", name: "Compact with a raid dropdown, question beside the minimap", flow: "two", askAt: "corner",
  blurb: "Sync tab: one line names the raid, with a dropdown to change it (the open list is shown in the crowded state); paste is behind a button unless the helper isn't running. Question: two steps in a small window under the minimap, which doesn't block the screen.",
  body(m, state) {
    const label = m.sel === "off" ? "Not a guild run" : m.sel ? rname(m.sel) : "Choose the raid";
    const open = state === "sync-crowded";
    const menu = open ? `<div class="tip menu" style="left:58px;top:34px;width:430px" role="listbox"><div class="menu-title">Raid events</div>
      ${m.list.map((id) => `<div class="mi ${id === m.sel ? "sel" : ""}" role="option" aria-selected="${id === m.sel}" ${id === m.sel ? "" : 'data-goto="sync-switch" tabindex="0"'}><span class="chk ${id === m.sel ? "on" : ""}" ${id === m.sel ? 'aria-label="Selected"' : ""}></span><span class="white">${esc(rname(id))}</span><span class="spacer"></span><span class="hint" style="font-size:12px">${esc(RAIDS[id].when)}${RAIDS[id].inst ? "" : " · no instance number"}${RAIDS[id].src === "pasted" ? " · pasted" : ""}</span></div>`).join("")}
      <div class="hr-div"></div><div class="mi" data-goto="sync-off" tabindex="0"><span class="chk"></span>Not a guild run</div><div class="mi"><span class="chk"></span><span class="grey">Remove a pasted raid…</span></div></div>` : "";
    const head = m.list.length ? `<div class="row" style="position:relative"><span class="gold">Raid:</span><button type="button" class="dd" style="font-size:14px;padding:4px 8px" aria-haspopup="listbox" aria-expanded="${open}" data-goto="${open ? "sync-chosen" : "sync-crowded"}">${esc(label)}</button>${menu}<span class="spacer"></span>${whereLine(m)}</div>` : "";
    const facts = m.sel && m.sel !== "off" ? `<div class="hint" style="margin:6px 0 2px">${raidFacts(m.sel)} · ${RAIDS[m.sel].awards} awards</div><div class="hint">${chosenLine(m)}${m.list.length > 1 ? " Changing it changes it for every officer in the group." : ""}</div>` : "";
    const bar = m.sel && m.sel !== "off" ? "" : `<div style="margin-top:6px">${statusBar(m)}</div>`;
    const pasteOpen = !m.helper;
    return `${head}${facts}${bar}<div style="height:8px"></div>${noraidBlock(m)}${helperLine(m)}<div class="hr-div" style="margin:10px 0 6px"></div>
      <div class="cols2"><div>${awardsOut(Object.assign({}, m, { list: m.list.length > 1 ? m.list : [] }), state)}</div>
      <div>${pasteOpen ? pasteBox(m, state) : `<div class="gold" style="margin-bottom:4px">Reserves in</div><div class="hint" style="margin-bottom:6px">The helper brings raid events in. Without it, paste a raid's reserves.</div>${btn("Paste reserves…", { goto: "sync-empty", title: "Opens the paste box (prototype: shown as the empty state)" })}`}
      ${m.pastedSel ? `<div class="row" style="margin-top:8px"><span class="hint">Pasted 19:42.</span>${btn("Remove", { size: "tiny", goto: "sync-remove" })}</div>` : ""}</div></div>`;
  },
};


const SYNC_GROUPS = [
  ["The raid question", ["ask-guild", "ask-raid", "ask-overlap", "ask-nomatch", "ask-fallback", "ask-again"]],
  ["Sync tab: raid chosen", ["sync-chosen", "sync-follower", "sync-crowded", "sync-switch"]],
  ["Sync tab: no raid", ["sync-off", "sync-undecided", "sync-gone", "sync-noraid", "sync-discard"]],
  ["Sync tab: without the helper", ["sync-empty", "sync-pasted", "sync-remove", "sync-refused"]],
];
const SYNC_LABELS = {
  "ask-guild": "Question: is this a guild run?", "ask-raid": "Question: which raid event (one matches)", "ask-overlap": "Question: two raids overlap",
  "ask-nomatch": "Question: no raid for this instance", "ask-fallback": "Question: asked because master loot is off", "ask-again": "Question: entering a different raid",
  "sync-chosen": "Sync: raid chosen by you", "sync-follower": "Sync: another officer's view", "sync-crowded": "Sync: most raids loaded", "sync-switch": "Sync: switching raid with awards",
  "sync-off": "Sync: not a guild run", "sync-undecided": "Sync: decided later", "sync-gone": "Sync: chosen raid left the list", "sync-noraid": "Sync: awards with no raid", "sync-discard": "Sync: discard awards with no raid",
  "sync-empty": "Sync: nothing loaded", "sync-pasted": "Sync: pasted raid, copy out", "sync-remove": "Sync: remove a pasted raid", "sync-refused": "Sync: paste refused",
};

function syncScene(state, V) {
  const S = SYNC_V[V.syncKey];
  const m = syncModel(state);
  let out = "";
  const zone = m.zone || "Ironforge";
  if (state.startsWith("ask-")) {
    out += askDialog(state, m, S);
    out += chat([sysLine("Seraphine Ashdown has joined the raid group.")]);
  } else {
    const w = V.syncKey === "b" ? 900 : 860;
    out += windowFrame("sync", S.body(m, state), { x: (1440 - w) / 2 - 40, y: 90, w, minH: 440, readOnly: m.viewer !== ME });
    out += syncDialog(state);
  }
  out += minimap({ badge: 0, zone });
  return out;
}

/* Prototype: picking a raid in the question selects it locally and enables Start. */
document.addEventListener("click", (e) => {
  const p = e.target.closest(".pick"); if (!p) return;
  const list = p.closest(".pick-list"); const box = p.closest(".frame");
  list.querySelectorAll(".pick").forEach((x) => { x.classList.remove("on"); const rb = x.querySelector(".rb"); rb.classList.remove("on"); rb.setAttribute("aria-checked", "false"); });
  p.classList.add("on"); const rb = p.querySelector(".rb"); rb.classList.add("on"); rb.setAttribute("aria-checked", "true");
  const start = [...box.querySelectorAll(".btn")].find((b) => b.textContent === "Start");
  if (start) { start.disabled = false; start.dataset.goto = p.dataset.off ? "sync-off" : "sync-chosen"; }
});
document.addEventListener("keydown", (e) => {
  const t = e.target; if ((e.key !== "Enter" && e.key !== " ") || !(t.matches(".pick, .pickrow, .mi[data-goto]"))) return;
  e.preventDefault(); t.click();
});
