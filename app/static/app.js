"use strict";

const state = { truck: null, summary: null, valued: null, proposal: null };

const $ = (id) => document.getElementById(id);

async function api(path, opts) {
    const r = await fetch(path, opts);
    if (!r.ok) {
        let msg = r.status + " " + r.statusText;
        try { const j = await r.json(); if (j.detail) msg = typeof j.detail === "string" ? j.detail : JSON.stringify(j.detail); } catch { }
        throw new Error(msg);
    }
    return r.json();
}

function toast(msg, isErr) {
    const t = $("toast");
    t.textContent = msg;
    t.className = "toast show" + (isErr ? " err" : "");
    setTimeout(() => (t.className = "toast"), 2600);
}

async function withBusy(btn, fn) {
    btn.classList.add("busy"); btn.disabled = true;
    try { await fn(); }
    catch (e) { toast(e.message, true); }
    finally { btn.classList.remove("busy"); btn.disabled = false; }
}

// --- config bar -------------------------------------------------------------
api("/api/config").then((c) => {
    $("cfg").innerHTML =
        `chat: <b>${c.chatDeployment}</b> &middot; index: <b>${c.searchIndex}</b><br>` +
        `db: <b>${c.cosmosDatabase}</b>`;
}).catch(() => { });

// --- trucks -----------------------------------------------------------------
api("/api/trucks").then((trucks) => {
    const grid = $("truckGrid");
    grid.innerHTML = "";
    trucks.forEach((t) => {
        const el = document.createElement("div");
        el.className = "card";
        el.innerHTML =
            `<h3>${t.model}</h3>` +
            `<div class="meta">${t.engine} &middot; ${t.axle} &middot; ${t.application}</div>` +
            `<div class="tags">${(t.highlights || []).map((h) => `<span class="tag">${h}</span>`).join("")}</div>`;
        el.onclick = () => {
            document.querySelectorAll(".card").forEach((c) => c.classList.remove("sel"));
            el.classList.add("sel");
            state.truck = t;
            state.summary = state.valued = state.proposal = null;
            $("outInterpret").textContent = "";
            $("outGround").innerHTML = "";
            $("outCompose").innerHTML = "";
            $("outApprove").innerHTML = "";
            $("btnInterpret").disabled = false;
            $("btnGround").disabled = $("btnCompose").disabled = $("btnApprove").disabled = true;
        };
        grid.appendChild(el);
    });
});

// --- interpret --------------------------------------------------------------
$("btnInterpret").onclick = () => withBusy($("btnInterpret"), async () => {
    state.summary = await api("/api/interpret", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ truckId: state.truck.id }),
    });
    $("outInterpret").textContent = JSON.stringify(state.summary, null, 2);
    $("btnGround").disabled = false;
});

// --- ground -----------------------------------------------------------------
$("btnGround").onclick = () => withBusy($("btnGround"), async () => {
    state.valued = await api("/api/ground", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ summary: state.summary }),
    });
    const items = state.valued.items || [];
    const srcs = state.valued._sources || [];
    $("outGround").innerHTML =
        items.map((it) =>
            `<div class="item"><b>${it.feature || ""}</b> - ${it.customerValue || ""}` +
            `<div class="src">${(it.evidence || "").slice(0, 200)} ${it.source ? "(source " + it.source + ")" : ""}</div></div>`
        ).join("") +
        (srcs.length ? `<div class="src" style="margin-top:8px">Retrieved: ${srcs.map((s) => "[" + s.n + "] " + s.title).join(", ")}</div>` : "");
    $("btnCompose").disabled = false;
});

// --- compose ----------------------------------------------------------------
$("btnCompose").onclick = () => withBusy($("btnCompose"), async () => {
    state.proposal = await api("/api/compose", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ summary: state.summary, valued: state.valued }),
    });
    const p = state.proposal;
    $("outCompose").innerHTML =
        `<div class="proposal"><h3>${p.title || ""}</h3>` +
        `<div class="src">For: ${p.customerName || "Customer"}</div>` +
        `<p>${p.headline || ""}</p>` +
        (p.sections || []).map((s) => `<div class="sec"><h4>${s.heading || ""}</h4><div>${s.body || ""}</div></div>`).join("") +
        `<p><em>${p.closing || ""}</em></p></div>`;
    $("btnApprove").disabled = false;
});

// --- approve ----------------------------------------------------------------
$("btnApprove").onclick = () => withBusy($("btnApprove"), async () => {
    const res = await api("/api/approve", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ quote: state.proposal, summary: state.summary, valued: state.valued }),
    });
    $("outApprove").innerHTML = `Saved to Cosmos as <b>${res.quoteId}</b>.`;
    toast("Quote saved to Cosmos");
    loadQuotes();
});

// --- saved quotes -----------------------------------------------------------
function loadQuotes() {
    api("/api/quotes").then((qs) => {
        $("quotes").innerHTML = qs.length
            ? qs.map((q) => `<div class="q"><div>${q.title || "(untitled)"}</div><div class="who">${q.customerName || ""} &middot; ${q.savedAt || ""}</div></div>`).join("")
            : `<div class="src">No quotes saved yet.</div>`;
    }).catch(() => { });
}
loadQuotes();

// --- chat -------------------------------------------------------------------
$("chatForm").onsubmit = (e) => {
    e.preventDefault();
    const input = $("chatInput");
    const q = input.value.trim();
    if (!q) return;
    input.value = "";
    addBubble(q, "me");
    const thinking = addBubble("...", "bot");
    api("/api/chat", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question: q }),
    }).then((res) => {
        const cites = (res.sources || []).map((s) => "[" + s.n + "] " + s.title).join(", ");
        thinking.innerHTML = (res.answer || "") + (cites ? `<div class="src" style="margin-top:6px">${cites}</div>` : "");
    }).catch((err) => { thinking.textContent = "Error: " + err.message; });
};

function addBubble(text, cls) {
    const b = document.createElement("div");
    b.className = "bubble " + cls;
    b.textContent = text;
    $("chatLog").appendChild(b);
    $("chatLog").scrollTop = $("chatLog").scrollHeight;
    return b;
}
