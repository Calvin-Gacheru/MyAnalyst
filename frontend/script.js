(() => {
  "use strict";

  /* ============================================================
     State + persistence
     ============================================================ */
  const LS_API_BASE = "myanalyst.apiBase";
  const LS_SESSIONS = "myanalyst.sessions"; // workspace_id -> { sessionId }
  const LS_LAST_WORKSPACE = "myanalyst.lastWorkspace";
  const LS_SIDEBAR_COLLAPSED = "myanalyst.sidebarCollapsed";
  const LS_FOCUS_MODE = "myanalyst.focusMode";

  // When served by the backend itself (the recommended `uvicorn main:app`
  // flow), the API lives at the same origin as this page, so default to
  // that and skip any setup. Only fall back to localhost:8000 when there's
  // no meaningful origin to infer from (e.g. opened as a local file://).
  const sameOriginDefault = location.protocol.startsWith("http") ? location.origin : "http://localhost:8000";

  const state = {
    apiBase: localStorage.getItem(LS_API_BASE) || sameOriginDefault,
    workspaceId: null,
    sessionId: null, // assigned by the backend on the first question of a workspace
    mode: "data", // "docs" when the workspace holds only documents (conversational layout)
  };

  function loadSessionMap(){
    try { return JSON.parse(localStorage.getItem(LS_SESSIONS) || "{}"); }
    catch { return {}; }
  }
  function saveSession(workspaceId, sessionId){
    const map = loadSessionMap();
    map[workspaceId] = { sessionId };
    localStorage.setItem(LS_SESSIONS, JSON.stringify(map));
    localStorage.setItem(LS_LAST_WORKSPACE, workspaceId);
  }

  /* ============================================================
     Small DOM helpers
     ============================================================ */
  const $ = (id) => document.getElementById(id);
  function escapeHtml(str){
    return String(str ?? "").replace(/[&<>"']/g, (c) => ({
      "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
    }[c]));
  }
  function el(tag, attrs = {}, children = []){
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)){
      if (k === "class") node.className = v;
      else if (k === "text") node.textContent = v;
      else if (k.startsWith("on") && typeof v === "function") node.addEventListener(k.slice(2), v);
      else node.setAttribute(k, v);
    }
    for (const child of [].concat(children)) if (child) node.appendChild(child);
    return node;
  }

  function showToast(message, type = "error"){
    const region = $("toast-region");
    const toast = el("div", { class: `toast ${type}`, text: message });
    region.appendChild(toast);
    setTimeout(() => { toast.style.opacity = "0"; toast.style.transition = "opacity .3s"; setTimeout(() => toast.remove(), 300); }, 5200);
  }

  async function runPrediction(){
    const targetDropdown = $("predict-target-dropdown");
    if (!state.workspaceId){ showToast("Upload a dataset first.", "error"); return; }
    if (!targetDropdown.value){ showToast("Select a target column to predict.", "error"); return; }
    // Option values carry the file too, since several datasets can share a column name.
    const { filename, column } = JSON.parse(targetDropdown.value);

    const btn = $("run-predict-btn");
    const loading = $("predict-loading");
    const results = $("predict-results");
    const narrative = $("predict-narrative");

    btn.disabled = true;
    loading.style.display = "block";
    results.style.display = "none";
    narrative.innerHTML = "";

    try{
      const data = await api(`/workspaces/${encodeURIComponent(state.workspaceId)}/predict`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ target_column: column, filename }),
      });

      narrative.appendChild(el("div", { class: "predict-narrative-head" }, [
        el("span", { class: "predict-narrative-title", text: `What drives ${column}` }),
        el("span", { class: "type-pill", text: data.problem_type }),
      ]));
      narrative.appendChild(renderMarkdown(data.predictive_summary || ""));

      // Show the container first so Plotly can measure its width.
      results.style.display = "block";
      plotThemed("predict-importance-plot", data.importance_plot, { sourceFile: filename });
      plotThemed("predict-performance-plot", data.performance_plot, { sourceFile: filename });
    } catch (err){
      showToast(`Error running model: ${err.message}`, "error");
    } finally {
      btn.disabled = false;
      loading.style.display = "none";
      scheduleChartIndex();
    }
  }

  /* ============================================================
     Backend fetch wrapper
     ============================================================ */
  async function api(path, options = {}){
    const url = state.apiBase.replace(/\/+$/, "") + path;
    let response;
    try{
      response = await fetch(url, options);
    } catch (networkErr){
      throw new Error(
        `Can't reach the MyAnalyst backend at ${state.apiBase}. ` +
        `Check that it's running (uvicorn main:app) and that the address is correct.`
      );
    }
    if (!response.ok){
      let detail = response.statusText;
      try { const body = await response.json(); detail = body.detail || JSON.stringify(body); } catch {}
      throw new Error(`${response.status}: ${detail}`);
    }
    if (response.status === 204) return null;
    return response.json();
  }

  /* ============================================================
     Settings modal
     ============================================================ */
  function openSettings(){
    $("api-base-input").value = state.apiBase;
    $("settings-modal").hidden = false;
    $("api-base-input").focus();
  }
  function closeSettings(){ $("settings-modal").hidden = true; }
  $("settings-btn").addEventListener("click", openSettings);
  $("settings-cancel").addEventListener("click", closeSettings);
  $("settings-modal").addEventListener("click", (e) => { if (e.target.id === "settings-modal") closeSettings(); });
  $("settings-save").addEventListener("click", () => {
    const value = $("api-base-input").value.trim();
    if (!value){ showToast("Enter a backend address first.", "error"); return; }
    state.apiBase = value.replace(/\/+$/, "");
    localStorage.setItem(LS_API_BASE, state.apiBase);
    closeSettings();
    showToast("Backend address saved.", "info");
  });

  /* ============================================================
     Upload flow
     ============================================================ */
  const dropzone = $("dropzone");
  const fileInput = $("file-input");

  dropzone.addEventListener("click", () => fileInput.click());
  dropzone.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " "){ e.preventDefault(); fileInput.click(); } });
  ["dragenter", "dragover"].forEach(evt => dropzone.addEventListener(evt, (e) => { e.preventDefault(); dropzone.classList.add("dragging"); }));
  ["dragleave", "drop"].forEach(evt => dropzone.addEventListener(evt, (e) => { e.preventDefault(); dropzone.classList.remove("dragging"); }));
  dropzone.addEventListener("drop", (e) => handleFiles(e.dataTransfer.files));
  fileInput.addEventListener("change", () => {
    handleFiles(fileInput.files);
    fileInput.value = "";
  });
  $("add-files-btn").addEventListener("click", () => fileInput.click());

  const ALLOWED_EXTENSIONS = [".csv", ".xlsx", ".pdf", ".docx", ".txt"];

  function handleFiles(fileList){
    const files = Array.from(fileList || []);
    const isAllowed = (f) => ALLOWED_EXTENSIONS.some((ext) => f.name.toLowerCase().endsWith(ext));
    const rejected = files.filter((f) => !isAllowed(f));
    if (rejected.length){
      showToast(`Skipped unsupported file(s): ${rejected.map((f) => f.name).join(", ")}`, "error");
    }
    const accepted = files.filter(isAllowed);
    if (accepted.length) uploadFiles(accepted);
  }

  const PROGRESS_MESSAGES = [
    "Cleaning currency symbols, dates, and stray columns…",
    "Imputing missing values and capping outliers…",
    "Indexing documents for semantic search…",
    "Reading documents and drafting starter questions…",
    "Writing a data dictionary…",
    "Choosing charts worth looking at…",
    "Drafting the executive summary…",
  ];
  let progressTimer = null;
  function startProgressCycle(){
    const status = $("progress-status");
    let i = 0;
    status.textContent = PROGRESS_MESSAGES[0];
    progressTimer = setInterval(() => {
      i = (i + 1) % PROGRESS_MESSAGES.length;
      status.style.opacity = "0";
      setTimeout(() => { status.textContent = PROGRESS_MESSAGES[i]; status.style.opacity = "1"; }, 200);
    }, 2200);
  }
  function stopProgressCycle(){ clearInterval(progressTimer); progressTimer = null; }

  // Uploads into the current workspace, or creates a new one when there isn't one yet.
  async function uploadFiles(files){
    const addingToExisting = Boolean(state.workspaceId);
    $("empty-state").hidden = true;
    $("dashboard").hidden = true;
    $("upload-progress").hidden = false;
    startProgressCycle();

    const formData = new FormData();
    files.forEach((f) => formData.append("files", f)); // must match FastAPI's `files` parameter

    try{
      const target = encodeURIComponent(state.workspaceId || "new");
      const data = await api(`/workspaces/${target}/files`, { method: "POST", body: formData });

      if (data.workspace_id !== state.workspaceId){
        state.workspaceId = data.workspace_id;
        state.sessionId = null;
      }
      saveSession(state.workspaceId, state.sessionId);
      renderDashboard(data, { resetChat: !addingToExisting });
      (data.errors || []).forEach((msg) => showToast(msg, "error"));
    } catch (err){
      showToast(err.message, "error");
      $("upload-progress").hidden = true;
      if (addingToExisting) $("dashboard").hidden = false;
      else $("empty-state").hidden = false;
    } finally {
      stopProgressCycle();
    }
  }

  /* ============================================================
     Dashboard rendering
     ============================================================ */
  const ACTION_LABELS = {
    strip_currency_and_cast_float: "currency",
    coerce_datetime: "datetime",
    drop_zero_variance: "dropped",
    flag_high_cardinality_id: "id flagged",
    downcast_float64: "downcast",
    downcast_int64: "downcast",
    convert_to_category: "category",
    impute_missing_numeric: "imputed",
    impute_missing_categorical: "imputed",
    cap_outliers_iqr: "outliers",
    flag_outliers_iqr: "outliers flagged",
  };

  // `data` is the full workspace state (every file, not just the latest upload).
  function renderDashboard(data, { resetChat = false } = {}){
    $("upload-progress").hidden = true;
    $("empty-state").hidden = true;
    $("dashboard").hidden = false;
    $("dataset-meta").hidden = false;
    $("new-analysis-btn").hidden = false;
    $("add-files-btn").hidden = false;

    const files = data.files || [];
    const tabularFiles = files.filter((f) => f.file_type === "tabular");
    const documentFiles = files.filter((f) => f.file_type === "document");
    setLayoutMode(documentFiles.length && !tabularFiles.length ? "docs" : "data");
    $("rail-file-count").textContent = files.length;
    $("dataset-name").textContent = files.length === 1 ? files[0].filename : `${files.length} files`;

    // Workspace files list
    let totalRows = 0;
    let totalChunks = 0;
    const fileList = $("workspace-files-list");
    fileList.innerHTML = "";
    files.forEach((f) => {
      const details = f.details || {};
      let detailsStr;
      if (f.file_type === "tabular"){
        detailsStr = `${(details.rows || 0).toLocaleString()} rows`;
        totalRows += details.rows || 0;
      } else {
        detailsStr = `${details.chunks || 0} chunks`;
        totalChunks += details.chunks || 0;
      }
      fileList.appendChild(el("li", { class: "file-item" }, [
        el("span", { class: "file-name", title: f.filename, text: `${f.file_type === "tabular" ? "📊" : "📄"} ${f.filename}` }),
        el("span", { class: "file-badge", text: `${f.file_type} | ${detailsStr}` }),
      ]));
    });

    const stats = [];
    if (totalRows) stats.push(`${totalRows.toLocaleString()} rows`);
    if (totalChunks) stats.push(`${totalChunks} document chunks`);
    $("dataset-stats").textContent = stats.join(" · ") || "No content indexed";

    // Documents get a digest with starter questions instead of the tabular executive summary.
    $("summary-card").hidden = !data.executive_summary;
    $("summary-text").replaceChildren(renderMarkdown(data.executive_summary || "—"));
    $("digest-card").hidden = !documentFiles.length;
    if (documentFiles.length) renderDigest(data.document_digests || []);

    // Tabular-only cards are shown whenever the workspace holds at least one dataset.
    const tabularCards = [
      $("chart-grid").closest(".card"),
      $("dictionary-body").closest(".card"),
      $("log-list").closest(".card"),
      $("predictive-card"),
    ];
    tabularCards.forEach((card) => { card.style.display = tabularFiles.length ? "block" : "none"; });

    if (tabularFiles.length){
      renderCharts(data.charts || []);
      renderDictionary(data.data_dictionary || []);
      renderCleaningLog(data.cleaning_log || []);
      populatePredictDropdown(data.data_dictionary || [], tabularFiles.length > 1);
    }

    loadBusinessRules();
    if (resetChat){
      resetChatThread();
      chartThreads.clear();
    }
    scheduleChartIndex();
  }

  // Documents-only workspaces are conversational: the chat moves into the main
  // column beneath the digest. Otherwise it lives in the right-hand rail.
  function setLayoutMode(mode){
    state.mode = mode;
    $("dashboard").classList.toggle("mode-docs", mode === "docs");
    const chatCard = $("chat-card");
    const home = mode === "docs" ? $("workspace") : $("copilot");
    if (chatCard.parentElement !== home) home.appendChild(chatCard);
    $("question-input").placeholder = mode === "docs"
      ? "Ask anything about your documents…"
      : "What drove the drop in March revenue?";
    const empty = $("chat-empty");
    if (empty) empty.textContent = chatEmptyText();
  }

  function renderDigest(digests){
    const list = $("digest-list");
    list.innerHTML = "";
    $("digest-count-label").textContent = `${digests.length} document${digests.length === 1 ? "" : "s"}`;

    const summarized = digests.filter((d) => d.summary);
    summarized.forEach((d) => {
      list.appendChild(el("div", { class: "digest-item" }, [
        el("div", { class: "digest-file", title: d.filename, text: d.filename }),
        el("p", { class: "digest-summary", text: d.summary }),
      ]));
    });
    if (!summarized.length){
      list.appendChild(el("p", { class: "digest-summary",
        text: "Your documents are indexed and ready — ask anything below and MyAnalyst will answer with page-level citations." }));
    }

    // Round-robin across documents so each one gets a starter question in the first few chips.
    const seen = new Set();
    const questions = [];
    const perDoc = digests.map((d) => d.starter_questions || []);
    for (let i = 0; questions.length < 6 && perDoc.some((qs) => i < qs.length); i++){
      perDoc.forEach((qs) => {
        const q = qs[i];
        if (q && questions.length < 6 && !seen.has(q.toLowerCase())){
          seen.add(q.toLowerCase());
          questions.push(q);
        }
      });
    }
    const container = $("starter-questions");
    container.innerHTML = "";
    questions.forEach((q) => {
      container.appendChild(el("button", { class: "starter-chip", type: "button", text: q, onclick: () => askQuestion(q) }));
    });
    $("starter-block").hidden = !questions.length;
  }

  function populatePredictDropdown(entries, showFile){
    const dropdown = $("predict-target-dropdown");
    dropdown.innerHTML = "";
    dropdown.appendChild(el("option", { value: "", text: "Select a target column…" }));
    entries.forEach((entry) => {
      const label = `${entry.column} (${entry.data_type})` + (showFile ? ` — ${entry.source_file}` : "");
      dropdown.appendChild(el("option", {
        value: JSON.stringify({ filename: entry.source_file, column: entry.column }),
        text: label,
      }));
    });
    $("predict-results").style.display = "none";
  }

  function renderCharts(charts){
    const grid = $("chart-grid");
    grid.innerHTML = "";
    $("chart-count-label").textContent = charts.length ? `${charts.length} chart${charts.length === 1 ? "" : "s"}` : "";

    charts.forEach((chart, idx) => {
      const targetId = `chart-${idx}`;
      const cell = el("div", { class: "chart-cell" });
      if (chart.plotly_json){
        cell.appendChild(el("div", { id: targetId, class: "chart-target" }));
        // Why the planner picked this chart, so it never reads as decoration.
        if (chart.rationale) cell.appendChild(el("p", { class: "chart-why", text: chart.rationale }));
      } else {
        cell.appendChild(el("div", { class: "chart-error", text: `“${chart.title}” couldn't be generated: ${chart.error || "unknown error"}` }));
      }
      grid.appendChild(cell);

      if (chart.plotly_json){
        try{
          plotThemed(targetId, chart.plotly_json, { sourceFile: chart.source_file });
        } catch (e){
          $(targetId).outerHTML = `<div class="chart-error">Couldn't render "${escapeHtml(chart.title)}".</div>`;
        }
      }
    });
  }

  // Renders a serialized Plotly figure with the dashboard's dark theme.
  // `target` is an element id or node, and must already be in the DOM.
  // Every inline chart gets an Expand button; the explorer copy passes `expanded`.
  // `sourceFile` is the dataset the chart was drawn from, when known.
  function plotThemed(target, plotlyJson, { expanded = false, sourceFile = null } = {}){
    const node = typeof target === "string" ? $(target) : target;
    const parsed = JSON.parse(plotlyJson);
    const layout = Object.assign({}, parsed.layout, {
      paper_bgcolor: "rgba(0,0,0,0)",
      plot_bgcolor: "rgba(0,0,0,0)",
      font: { color: "#c3cadf", family: "Inter, sans-serif", size: expanded ? 13 : 11 },
      margin: expanded ? { t: 56, r: 28, l: 64, b: 60 } : { t: 36, r: 14, l: 44, b: 40 },
      colorway: ["#4fe0d1", "#8c7cfb", "#f2a65a", "#f38ba0"],
    });
    Plotly.newPlot(node, parsed.data, layout, { displayModeBar: expanded, displaylogo: false, responsive: true });
    if (!expanded) attachExpandButton(node, plotlyJson, sourceFile);
  }

  /* ============================================================
     Chart explorer: expanded chart + jump list + chart-scoped Q&A
     ============================================================ */
  const chartSources = new WeakMap(); // plot node -> { plotlyJson, sourceFile }
  const chartThreads = new Map(); // plotly JSON -> [{ role, content }] asked in the explorer
  const chartPending = new Set(); // plotly JSON of charts with a question in flight
  const explorer = { charts: [], index: 0 };

  function attachExpandButton(node, plotlyJson, sourceFile){
    chartSources.set(node, { plotlyJson, sourceFile });
    node.classList.add("expandable-chart");
    scheduleChartIndex();
    // Re-plotting the same node (e.g. re-running a model) keeps its existing button.
    if (node.querySelector(":scope > .chart-expand-btn")) return;
    const btn = el("button", {
      class: "chart-expand-btn", type: "button", title: "Expand and ask about this chart", "aria-label": "Expand chart and ask about it",
      onclick: () => openChartModal(node),
    });
    btn.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 3 21 3 21 9"></polyline><polyline points="9 21 3 21 3 15"></polyline><line x1="21" y1="3" x2="14" y2="10"></line><line x1="3" y1="21" x2="10" y2="14"></line></svg><span>Expand</span>';
    node.appendChild(btn);
  }

  function figureTitle(plotlyJson){
    const title = JSON.parse(plotlyJson).layout?.title;
    return ((typeof title === "string" ? title : title?.text) || "").replace(/<[^>]*>/g, " ").trim();
  }

  // Charts inside a card that script.js hid (inline display:none / [hidden]) are stale, e.g. old model results.
  function isShown(node){
    if (!node.isConnected) return false;
    for (let n = node; n && n !== document.body; n = n.parentElement){
      if (n.hidden || n.style.display === "none") return false;
    }
    return true;
  }

  function chartGroup(node){
    if (node.closest("#chat-thread")) return "Chat answers";
    return node.closest(".card")?.querySelector(".card-head h3")?.textContent || "Charts";
  }

  // Every live chart on the page in reading order: exploratory, predictive, then chat answers.
  function listCharts(){
    const perGroup = {};
    return Array.from(document.querySelectorAll(".expandable-chart")).filter(isShown).map((node) => {
      const { plotlyJson, sourceFile } = chartSources.get(node);
      const group = chartGroup(node);
      perGroup[group] = (perGroup[group] || 0) + 1;
      return { node, group, plotlyJson, sourceFile, title: figureTitle(plotlyJson) || `Chart ${perGroup[group]}` };
    });
  }

  function chartJumpItems(charts, { activeIndex = -1, onPick }){
    const items = [];
    let lastGroup = null;
    charts.forEach((chart, i) => {
      if (chart.group !== lastGroup){
        items.push(el("li", { class: "chart-jump-group", text: chart.group }));
        lastGroup = chart.group;
      }
      const asked = (chartThreads.get(chart.plotlyJson) || []).filter((m) => m.role === "user").length;
      const btn = el("button", { class: "chart-jump", type: "button", title: chart.title, onclick: () => onPick(i) }, [
        el("span", { class: "chart-jump-title", text: chart.title }),
        asked ? el("span", { class: "chart-jump-count", title: `${asked} question${asked === 1 ? "" : "s"} asked`, text: String(asked) }) : null,
      ]);
      if (i === activeIndex){ btn.classList.add("active"); btn.setAttribute("aria-current", "true"); }
      items.push(el("li", {}, [btn]));
    });
    return items;
  }

  // Charts appear and disappear from several places, so the sidebar index re-renders once per frame.
  let chartIndexFrame = 0;
  function scheduleChartIndex(){
    cancelAnimationFrame(chartIndexFrame);
    chartIndexFrame = requestAnimationFrame(renderChartIndex);
  }
  function renderChartIndex(){
    const charts = listCharts();
    $("chart-index-card").hidden = !charts.length;
    $("rail-charts-btn").hidden = !charts.length;
    $("rail-chart-count").textContent = charts.length;
    $("chart-index-count").textContent = charts.length ? `${charts.length} chart${charts.length === 1 ? "" : "s"}` : "";
    $("chart-index").replaceChildren(...chartJumpItems(charts, { onPick: (i) => openChartModal(charts[i].node) }));
  }
  $("rail-charts-btn").addEventListener("click", () => {
    const first = listCharts()[0];
    if (first) openChartModal(first.node);
  });

  let chartModalReturnFocus = null;
  function openChartModal(node){
    const charts = listCharts();
    if (!charts.length) return;
    if ($("chart-modal").hidden){
      chartModalReturnFocus = document.activeElement;
      $("chart-modal").hidden = false;
      document.body.classList.add("modal-open");
    }
    explorer.charts = charts;
    showExplorerChart(Math.max(charts.findIndex((c) => c.node === node), 0));
    $("chart-ask-input").focus();
  }

  function showExplorerChart(index){
    const { charts } = explorer;
    explorer.index = (index + charts.length) % charts.length;
    const chart = charts[explorer.index];
    $("chart-modal-title").textContent = chart.title;
    $("chart-modal-group").textContent = chart.sourceFile ? `${chart.group} · ${chart.sourceFile}` : chart.group;
    $("chart-modal-pos").textContent = `${explorer.index + 1} / ${charts.length}`;
    $("chart-prev").disabled = $("chart-next").disabled = charts.length < 2;
    renderExplorerNav();
    renderChartThread();

    // Plot after the overlay is visible so Plotly sizes to the full panel.
    const plot = $("chart-modal-plot");
    Plotly.purge(plot);
    plot.replaceChildren();
    try{
      plotThemed(plot, chart.plotlyJson, { expanded: true });
    } catch (e){
      plot.replaceChildren(el("div", { class: "chart-error", text: `Couldn't render "${chart.title}".` }));
    }
  }

  function renderExplorerNav(){
    const list = $("chart-nav-list");
    list.replaceChildren(...chartJumpItems(explorer.charts, { activeIndex: explorer.index, onPick: showExplorerChart }));
    list.querySelector(".active")?.scrollIntoView({ block: "nearest", inline: "nearest" });
  }

  const CHART_STARTERS = ["What's the main takeaway?", "Anything unusual worth a closer look?", "What should we do about this?"];

  function renderChartThread(){
    const chart = explorer.charts[explorer.index];
    const messages = chartThreads.get(chart.plotlyJson) || [];
    const pending = chartPending.has(chart.plotlyJson);
    const thread = $("chart-ask-thread");
    thread.innerHTML = "";

    if (!messages.length){
      thread.appendChild(el("div", { class: "chart-ask-empty" }, [
        el("p", { class: "chat-empty", text: "Ask anything about this chart. MyAnalyst reads the plotted values and answers with your data dictionary and business rules in mind." }),
        el("div", { class: "starter-questions" }, CHART_STARTERS.map((q) =>
          el("button", { class: "starter-chip", type: "button", text: q, onclick: () => askAboutChart(q) })
        )),
      ]));
    }
    messages.forEach((m) => thread.appendChild(m.role === "user"
      ? el("div", { class: "msg msg-user" }, [el("div", { class: "bubble", text: m.content })])
      : el("div", { class: "msg msg-assistant" }, [el("div", { class: "bubble" }, [renderMarkdown(m.content, [], "answer-text")])])
    ));
    if (pending){
      thread.appendChild(el("div", { class: "msg msg-assistant" }, [
        el("div", { class: "thinking-card" }, [
          el("div", { class: "thinking-head" }, [el("div", { class: "thinking-dots" }, [el("i"), el("i"), el("i")]), el("span", { text: "Reading the chart" })]),
        ]),
      ]));
    }
    $("chart-ask-btn").disabled = pending;
    $("chart-ask-input").disabled = pending;
    thread.querySelectorAll(".starter-chip").forEach((chip) => { chip.disabled = pending; });
    thread.scrollTop = thread.scrollHeight;
  }

  // Each chart keeps its own thread for the life of the page, so jumping away and back resumes it.
  async function askAboutChart(question){
    const chart = explorer.charts[explorer.index];
    if (!question || !chart || !state.workspaceId || chartPending.has(chart.plotlyJson)) return;
    const key = chart.plotlyJson;
    if (!chartThreads.has(key)) chartThreads.set(key, []);
    const messages = chartThreads.get(key);
    const history = messages.slice(-8);
    messages.push({ role: "user", content: question });
    chartPending.add(key);
    $("chart-ask-input").value = "";
    renderChartThread();

    let failed = false;
    try{
      const data = await api(`/workspaces/${encodeURIComponent(state.workspaceId)}/chart-qa`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question, plotly_json: key, chart_title: chart.title, source_file: chart.sourceFile || null, history }),
      });
      messages.push({ role: "assistant", content: data.answer || "No answer was returned." });
    } catch (err){
      failed = true;
      messages.pop();
      showToast(err.message, "error");
    } finally {
      chartPending.delete(key);
      scheduleChartIndex();
      // The user may have jumped to another chart (or closed the explorer) while waiting.
      if (!$("chart-modal").hidden && explorer.charts[explorer.index]?.plotlyJson === key){
        renderChartThread();
        renderExplorerNav();
        if (failed) $("chart-ask-input").value = question;
        $("chart-ask-input").focus();
      }
    }
  }

  $("chart-ask-form").addEventListener("submit", (e) => {
    e.preventDefault();
    askAboutChart($("chart-ask-input").value.trim());
  });
  $("chart-ask-input").addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey){
      e.preventDefault();
      $("chart-ask-form").requestSubmit();
    }
  });

  function closeChartModal(){
    if ($("chart-modal").hidden) return;
    Plotly.purge("chart-modal-plot");
    $("chart-modal").hidden = true;
    document.body.classList.remove("modal-open");
    if (chartModalReturnFocus?.isConnected) chartModalReturnFocus.focus();
    chartModalReturnFocus = null;
  }
  $("chart-modal-close").addEventListener("click", closeChartModal);
  $("chart-prev").addEventListener("click", () => showExplorerChart(explorer.index - 1));
  $("chart-next").addEventListener("click", () => showExplorerChart(explorer.index + 1));
  $("chart-modal").addEventListener("click", (e) => { if (e.target.id === "chart-modal") closeChartModal(); });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeChartModal();
    // Arrow keys flip between charts, except while typing a question.
    else if (!$("chart-modal").hidden && (e.key === "ArrowLeft" || e.key === "ArrowRight") && !e.target.closest?.("textarea, input")){
      e.preventDefault();
      showExplorerChart(explorer.index + (e.key === "ArrowRight" ? 1 : -1));
    }
  });

  function renderDictionary(entries){
    const body = $("dictionary-body");
    body.innerHTML = "";
    entries.forEach((entry) => {
      body.appendChild(el("tr", {}, [
        el("td", { class: "col-name", text: entry.column }),
        el("td", { text: entry.business_meaning || "—" }),
        el("td", {}, [el("span", { class: "type-pill", text: entry.data_type })]),
        el("td", { text: entry.notes || "" }),
      ]));
    });
  }

  function renderCleaningLog(log){
    const list = $("log-list");
    list.innerHTML = "";
    $("log-count-label").textContent = log.length ? `${log.length} change${log.length === 1 ? "" : "s"}` : "";
    if (!log.length){
      list.appendChild(el("p", { class: "rule-empty", text: "No changes were needed — the data came in clean." }));
      return;
    }
    log.forEach((row) => {
      const tagLabel = ACTION_LABELS[row.action] || row.action.replace(/_/g, " ");
      list.appendChild(el("div", { class: "log-row" }, [
        el("span", { class: "tag", text: tagLabel }),
        el("div", { class: "detail" }, [
          el("b", { text: row.column + ": " }),
          document.createTextNode(row.detail),
        ]),
      ]));
    });
  }

  /* ============================================================
     Business rules
     ============================================================ */
  async function loadBusinessRules(){
    try{
      const rules = await api(`/workspaces/${encodeURIComponent(state.workspaceId)}/business-rules`);
      renderRuleChips(rules);
    } catch (err){
      showToast(err.message, "error");
    }
  }

  function renderRuleChips(rules){
    const container = $("rule-chips");
    container.innerHTML = "";
    $("rule-empty").hidden = rules.length > 0;
    $("rail-rule-count").textContent = rules.length;
    rules.forEach((rule) => {
      container.appendChild(el("div", { class: "rule-chip" }, [
        el("span", { text: rule.rule_text }),
      ]));
    });
  }

  $("rule-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const input = $("rule-input");
    const text = input.value.trim();
    if (!text || !state.workspaceId) return;
    const submitBtn = e.target.querySelector("button");
    submitBtn.disabled = true;
    try{
      await api(`/workspaces/${encodeURIComponent(state.workspaceId)}/business-rules`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ rule_text: text }),
      });
      input.value = "";
      await loadBusinessRules();
    } catch (err){
      showToast(err.message, "error");
    } finally {
      submitBtn.disabled = false;
    }
  });

  /* ============================================================
     Q&A chat
     ============================================================ */
  function chatEmptyText(){
    return state.mode === "docs"
      ? "Ask anything about your documents — every answer cites the file and page it came from. Hover a citation to preview the passage."
      : "Ask about your data or documents — MyAnalyst routes the question, runs the analysis or searches the documents, and cites its sources.";
  }

  function resetChatThread(){
    const thread = $("chat-thread");
    thread.innerHTML = "";
    thread.appendChild(el("p", { class: "chat-empty", id: "chat-empty", text: chatEmptyText() }));
    scheduleChartIndex();
  }

  function appendUserMessage(text){
    const empty = $("chat-empty");
    if (empty) empty.remove();
    const thread = $("chat-thread");
    thread.appendChild(el("div", { class: "msg msg-user" }, [
      el("div", { class: "bubble", text }),
    ]));
    thread.scrollTop = thread.scrollHeight;
  }

  const THINKING_STEPS = {
    docs: ["Routing your question", "Searching your documents", "Writing the answer"],
    data: ["Routing your question", "Planning the analysis", "Writing and running code", "Checking the result", "Writing the answer"],
  };
  const THINKING_STEP_SECONDS = 3;

  // /qa answers in one response, so these live steps are paced estimates of the
  // pipeline; the real trace (buildTrace) replaces them once the answer arrives.
  function appendThinkingRow(){
    const thread = $("chat-thread");
    const labels = THINKING_STEPS[state.mode === "docs" ? "docs" : "data"];
    const items = labels.map((label) => el("li", { class: "step" }, [el("span", { class: "step-mark" }), el("span", { text: label })]));
    const elapsed = el("span", { class: "thinking-elapsed", text: "0s" });
    const row = el("div", { class: "msg msg-assistant", id: "thinking-row" }, [
      el("div", { class: "thinking-card" }, [
        el("div", { class: "thinking-head" }, [
          el("div", { class: "thinking-dots" }, [el("i"), el("i"), el("i")]),
          el("span", { text: "Working on it" }),
          elapsed,
        ]),
        el("ol", { class: "thinking-steps" }, items),
      ]),
    ]);
    thread.appendChild(row);
    thread.scrollTop = thread.scrollHeight;

    const started = Date.now();
    const paint = (current) => items.forEach((li, i) => {
      li.classList.toggle("done", i < current);
      li.classList.toggle("active", i === current);
    });
    paint(0);
    const timer = setInterval(() => {
      const secs = Math.floor((Date.now() - started) / 1000);
      elapsed.textContent = `${secs}s`;
      // Hold on the last step until the answer actually arrives.
      paint(Math.min(Math.floor(secs / THINKING_STEP_SECONDS), items.length - 1));
    }, 1000);
    return () => { clearInterval(timer); row.remove(); };
  }

  const INTENT_LABELS = { quant: "data analysis", doc: "documents", hybrid: "data + documents" };

  // The stages that actually ran, reconstructed from the /qa response fields.
  function buildTrace(response){
    const intent = response.intent;
    if (!INTENT_LABELS[intent]) return null;
    const steps = [{ label: INTENT_LABELS[intent], tone: "intent", title: "How MyAnalyst routed this question" }];
    if (intent === "doc" || intent === "hybrid"){
      const n = (response.sources || []).length;
      steps.push({ label: n ? `${n} source${n === 1 ? "" : "s"} cited` : "searched documents" });
    }
    if ((intent === "quant" || intent === "hybrid") && response.generated_code){
      steps.push({ label: "wrote code" });
      if (response.attempts > 1){
        const errors = (response.errors || []).map((e) => e.length > 300 ? `${e.slice(0, 300)}…` : e);
        steps.push({ label: `self-corrected · ${response.attempts} attempts`, tone: "warn", title: errors.join("\n\n") || undefined });
      } else {
        steps.push({ label: "ran in sandbox" });
      }
    }
    steps.push({ label: "answered", tone: "done" });
    return el("ol", { class: "msg-trace", "aria-label": "What MyAnalyst did" }, steps.map((s) =>
      el("li", { class: `trace-step${s.tone ? ` trace-${s.tone}` : ""}`, text: s.label, ...(s.title ? { title: s.title } : {}) })
    ));
  }

  function appendAssistantMessage(response){
    const thread = $("chat-thread");
    const trace = buildTrace(response);

    const sources = response.sources || [];
    const bubbleChildren = [
      renderMarkdown(response.answer || "No answer was returned.", sources, "answer-text"),
    ];

    const plotlyJson = response.execution_output && response.execution_output.plotly_json;
    const chartTarget = plotlyJson ? el("div", { class: "chat-chart" }) : null;
    if (chartTarget) bubbleChildren.push(chartTarget);

    if (sources.length){
      bubbleChildren.push(el("div", { class: "msg-sources" }, sources.map((src) =>
        withCitePreview(el("span", { class: "source-chip", text: sourceLabel(src) }), src)
      )));
    }

    if (response.generated_code){
      const details = el("details", { class: "code-toggle" }, [
        el("summary", { text: "View generated code" }),
        el("pre", {}, [el("code", { text: response.generated_code })]),
      ]);
      bubbleChildren.push(details);
    }

    const msg = el("div", { class: "msg msg-assistant" }, [
      el("div", { class: "bubble" }, bubbleChildren),
      trace,
    ]);
    thread.appendChild(msg);

    // Plot only after the bubble is attached so Plotly can measure its width.
    if (chartTarget){
      try{
        plotThemed(chartTarget, plotlyJson);
      } catch (e){
        chartTarget.replaceWith(el("div", { class: "chart-error", text: "Couldn't render the chart for this answer." }));
      }
    }
    thread.scrollTop = thread.scrollHeight;
  }

  /* ============================================================
     Citations: inline [file, p. N] pills + glass hover previews
     ============================================================ */
  function sourceLabel(src){
    return src.page ? `${src.filename} · p. ${src.page}` : src.filename;
  }

  function withCitePreview(node, src){
    if (!src || !src.excerpt) return node;
    node.classList.add("has-tip");
    node.tabIndex = 0;
    node.dataset.citeLabel = sourceLabel(src);
    node.dataset.citeExcerpt = src.excerpt;
    return node;
  }

  // Matches a single citation like "policy.pdf, p. 3" / "policy.pdf, page 3" / "policy.pdf".
  const CITE_PART = /^\s*(.+?\.(?:pdf|docx|txt))(?:\s*,\s*(?:p\.|pp\.|page)\s*(\d+)[^,]*)?\s*$/i;

  function findSource(sources, filename, page){
    const sameFile = sources.filter((s) => s.filename.toLowerCase() === filename.toLowerCase());
    return sameFile.find((s) => String(s.page) === String(page)) || sameFile[0] || null;
  }

  // The RAG prompt asks the model to cite inline as [file.pdf, p. 3]; turn each
  // bracket whose file matches a returned source into a hoverable pill. Built
  // from text nodes only, so the answer is never interpreted as HTML.
  function renderAnswerWithCitations(text, sources){
    if (!sources.length) return [document.createTextNode(text)];
    const nodes = [];
    let last = 0;
    for (const match of text.matchAll(/\[([^\[\]\n]{3,200})\]/g)){
      const parts = match[1].split(";").map((p) => p.match(CITE_PART));
      if (!parts.every(Boolean)) continue;
      nodes.push(document.createTextNode(text.slice(last, match.index)));
      parts.forEach(([, filename, page], i) => {
        if (i) nodes.push(document.createTextNode(" "));
        // The preview's own label shows the page the excerpt actually came from.
        const label = page ? `${filename} · p. ${page}` : filename;
        nodes.push(withCitePreview(el("span", { class: "cite", text: label }), findSource(sources, filename, page)));
      });
      last = match.index + match[0].length;
    }
    nodes.push(document.createTextNode(text.slice(last)));
    return nodes;
  }

  /* ============================================================
     Markdown answers (marked + DOMPurify from the CDN)
     ============================================================ */
  const MD_READY = typeof marked !== "undefined" && typeof DOMPurify !== "undefined";
  if (MD_READY){
    marked.setOptions({ gfm: true, breaks: true });
    DOMPurify.addHook("afterSanitizeAttributes", (node) => {
      if (node.tagName === "A"){ node.setAttribute("target", "_blank"); node.setAttribute("rel", "noopener noreferrer"); }
    });
  }

  // Renders LLM markdown into sanitized DOM, then turns [file, p. N] citations in
  // its text (outside code) into pills. Falls back to plain text if the CDN failed.
  function renderMarkdown(text, sources = [], className = ""){
    const container = el("div", { class: `md ${className}`.trim() });
    if (!MD_READY){
      container.classList.add("md-plain");
      renderAnswerWithCitations(text, sources).forEach((n) => container.appendChild(n));
      return container;
    }
    container.innerHTML = DOMPurify.sanitize(marked.parse(text));
    if (sources.length){
      const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT, {
        acceptNode: (n) => n.parentElement.closest("code, pre") ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
      });
      const textNodes = [];
      while (walker.nextNode()) textNodes.push(walker.currentNode);
      textNodes.forEach((node) => {
        if (!node.nodeValue.includes("[")) return;
        const frag = document.createDocumentFragment();
        renderAnswerWithCitations(node.nodeValue, sources).forEach((n) => frag.appendChild(n));
        node.replaceWith(frag);
      });
    }
    return container;
  }

  const citeTip = $("cite-tip");
  let citeTipAnchor = null;

  function showCiteTip(anchor){
    citeTipAnchor = anchor;
    const excerpt = anchor.dataset.citeExcerpt.replace(/\s+/g, " ").trim();
    $("cite-tip-label").textContent = anchor.dataset.citeLabel;
    $("cite-tip-text").textContent = excerpt.length > 600 ? excerpt.slice(0, 600).trimEnd() + "…" : excerpt;
    citeTip.hidden = false;
    positionCiteTip();
    requestAnimationFrame(() => citeTip.classList.add("visible"));
  }

  // Prefer above the citation; flip below when there's no room. Clamp to a 16px gutter.
  function positionCiteTip(){
    const anchor = citeTipAnchor;
    const rect = anchor.getBoundingClientRect();
    const tipRect = citeTip.getBoundingClientRect();
    const gutter = 16;
    const above = rect.top - tipRect.height - 10;
    const top = above >= gutter ? above : Math.min(rect.bottom + 10, window.innerHeight - tipRect.height - gutter);
    const left = Math.min(Math.max(rect.left + rect.width / 2 - tipRect.width / 2, gutter), window.innerWidth - tipRect.width - gutter);
    citeTip.style.top = `${Math.max(top, gutter)}px`;
    citeTip.style.left = `${left}px`;
  }

  function hideCiteTip(){
    citeTipAnchor = null;
    citeTip.classList.remove("visible");
    citeTip.hidden = true;
  }

  document.addEventListener("mouseover", (e) => {
    const anchor = e.target.closest?.("[data-cite-excerpt]");
    if (anchor && anchor !== citeTipAnchor) showCiteTip(anchor);
    else if (!anchor && citeTipAnchor) hideCiteTip();
  });
  document.addEventListener("focusin", (e) => {
    const anchor = e.target.closest?.("[data-cite-excerpt]");
    if (anchor) showCiteTip(anchor);
  });
  document.addEventListener("focusout", (e) => { if (e.target === citeTipAnchor) hideCiteTip(); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && citeTipAnchor) hideCiteTip(); });
  // The tooltip is position:fixed, so follow the citation on scroll (focusing one
  // scrolls it into view) and drop it once the citation leaves its scroll box.
  document.addEventListener("scroll", () => {
    if (!citeTipAnchor) return;
    const box = (citeTipAnchor.closest(".chat-thread") || document.documentElement).getBoundingClientRect();
    const rect = citeTipAnchor.getBoundingClientRect();
    if (rect.bottom < box.top || rect.top > box.bottom) hideCiteTip();
    else positionCiteTip();
  }, true);

  /* ============================================================
     Asking questions
     ============================================================ */
  async function askQuestion(question){
    if (!state.workspaceId){ showToast("Upload a dataset first.", "error"); return; }
    const input = $("question-input");
    if (!question || $("ask-btn").disabled) return;

    appendUserMessage(question);
    // In the conversational layout the chat sits below the digest; bring it into view.
    if (state.mode === "docs") $("chat-card").scrollIntoView({ behavior: "smooth", block: "end" });
    input.value = "";
    $("ask-btn").disabled = true;
    input.disabled = true;
    document.querySelectorAll("#starter-questions .starter-chip").forEach((chip) => { chip.disabled = true; });
    const stopThinking = appendThinkingRow();

    try{
      const response = await api(`/workspaces/${encodeURIComponent(state.workspaceId)}/qa`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ question, session_id: state.sessionId }),
      });
      state.sessionId = response.session_id;
      saveSession(state.workspaceId, state.sessionId);
      stopThinking();
      appendAssistantMessage(response);
    } catch (err){
      stopThinking();
      showToast(err.message, "error");
    } finally {
      $("ask-btn").disabled = false;
      input.disabled = false;
      document.querySelectorAll("#starter-questions .starter-chip").forEach((chip) => { chip.disabled = false; });
      input.focus();
    }
  }

  $("ask-form").addEventListener("submit", (e) => {
    e.preventDefault();
    askQuestion($("question-input").value.trim());
  });

  $("question-input").addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey){
      e.preventDefault();
      $("ask-form").requestSubmit();
    }
  });

  /* ============================================================
     Reset / new analysis
     ============================================================ */
  $("run-predict-btn").addEventListener("click", runPrediction);

  /* ============================================================
     Collapsible left sidebar
     ============================================================ */
  function setSidebarCollapsed(collapsed){
    $("dashboard").classList.toggle("sidebar-collapsed", collapsed);
    const toggle = $("sidebar-toggle");
    toggle.setAttribute("aria-expanded", String(!collapsed));
    const label = collapsed ? "Expand sidebar" : "Collapse sidebar";
    toggle.title = label;
    toggle.setAttribute("aria-label", label);
    localStorage.setItem(LS_SIDEBAR_COLLAPSED, collapsed ? "1" : "0");
    // Plotly charts size to their container; let them catch up after the grid animates.
    setTimeout(() => window.dispatchEvent(new Event("resize")), 320);
  }
  $("sidebar-toggle").addEventListener("click", () => {
    setSidebarCollapsed(!$("dashboard").classList.contains("sidebar-collapsed"));
  });
  document.querySelectorAll("[data-expand-sidebar]").forEach((btn) => {
    btn.addEventListener("click", () => setSidebarCollapsed(false));
  });
  if (localStorage.getItem(LS_SIDEBAR_COLLAPSED) === "1") setSidebarCollapsed(true);

  /* ============================================================
     Focus mode: hide the dashboard, chat takes the full width
     ============================================================ */
  function setFocusMode(on){
    $("dashboard").classList.toggle("focus-mode", on);
    const toggle = $("focus-toggle");
    toggle.setAttribute("aria-pressed", String(on));
    const label = on ? "Exit focus mode" : "Enter focus mode";
    toggle.title = label;
    toggle.setAttribute("aria-label", label);
    localStorage.setItem(LS_FOCUS_MODE, on ? "1" : "0");
    // Chat charts resize to the wider column; dashboard charts redraw when they reappear.
    window.dispatchEvent(new Event("resize"));
  }
  $("focus-toggle").addEventListener("click", () => {
    setFocusMode(!$("dashboard").classList.contains("focus-mode"));
  });
  if (localStorage.getItem(LS_FOCUS_MODE) === "1") setFocusMode(true);

  $("new-analysis-btn").addEventListener("click", () => {
    state.workspaceId = null;
    state.sessionId = null;
    localStorage.removeItem(LS_LAST_WORKSPACE);
    $("dashboard").hidden = true;
    $("dataset-meta").hidden = true;
    $("new-analysis-btn").hidden = true;
    $("add-files-btn").hidden = true;
    $("predict-results").style.display = "none";
    resetChatThread();
    chartThreads.clear();
    $("empty-state").hidden = false;
  });

  /* ============================================================
     Restore the last workspace on page load
     ============================================================ */
  async function loadChatHistory(){
    if (!state.sessionId) return;
    const messages = await api(
      `/workspaces/${encodeURIComponent(state.workspaceId)}/chat-history?session_id=${encodeURIComponent(state.sessionId)}`
    );
    messages.forEach((m) => {
      if (m.role === "user") appendUserMessage(m.content);
      else appendAssistantMessage({ answer: m.content });
    });
  }

  async function restoreLastWorkspace(){
    const workspaceId = localStorage.getItem(LS_LAST_WORKSPACE);
    if (!workspaceId) return;
    try{
      const data = await api(`/workspaces/${encodeURIComponent(workspaceId)}`);
      state.workspaceId = workspaceId;
      state.sessionId = loadSessionMap()[workspaceId]?.sessionId || null;
      renderDashboard(data, { resetChat: true });
      await loadChatHistory();
    } catch (err){
      // A deleted workspace is forgotten; a backend that's merely down is retried next load.
      if (err.message.startsWith("404")) localStorage.removeItem(LS_LAST_WORKSPACE);
      else showToast(err.message, "error");
    }
  }

  restoreLastWorkspace();

})();
