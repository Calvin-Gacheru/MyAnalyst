## WHAT MYANALYST HAS EVOLVED INTO
The MyAnalyst project has successfully evolved from a conceptual data agent into a secure, autonomous platform combining deterministic data science pipelines with self-correcting LLM orchestration.

* **Core Architecture & State Management:** A FastAPI backend coordinates the system, utilizing a SQLite database (`memory.py`) to permanently store uploaded datasets, chat histories, and user-defined business rules (e.g., "always ignore refunded items"). Pydantic schemas (`schemas.py`) strictly enforce the API request and response contracts.
* **Deterministic Data Cleaning:** The `preprocessing.py` module automatically sanitizes raw CSVs before any LLM intervention. This mechanical pipeline strips currencies, coerces datetimes, drops zero-variance columns, flags high-cardinality IDs, imputes missing values (using the mean for normal distributions and the median for skewed data), and caps outliers via Interquartile Range (IQR) bounds.
* **LangGraph Orchestration:** The `graph.py` module powers two distinct state machines:
* **Proactive EDA:** Runs automatically upon dataset upload to select 3 to 4 optimal charts based on column data types and trigger baseline forecasts.
* **Cyclic Q&A:** A self-correcting loop that handles user questions. The agent plans the logic, writes Pandas/Plotly code, and executes it. If a syntax error occurs, the graph captures the Python traceback and routes it back to the Coder node for immediate self-correction (up to 3 retries).
* **Secure Docker Sandbox:** The application executes untrusted LLM-generated code inside a network-isolated Docker container (`sandbox.py` and `Dockerfile.sandbox`) rather than the local host process. It features read-only data mounts, Fedora SELinux volume compatibility (via `:z` flags), unified namespace execution to prevent list-comprehension scoping bugs, and hard limits on memory and CPU to prevent Out-Of-Memory (OOM) crashes.
* **Autonomous Time-Series Forecasting:** The system automatically analyzes datetime columns and routes the data to the optimal statistical model. High-frequency or irregular data is sent to Meta's Prophet, while structured periodic data is routed to Auto-ARIMA/SARIMA (using `pmdarima` and `statsmodels`).
* **Plain-English Business Translations:** The application extracts concrete statistical insights—like averages, data ranges, top categories, and trend trajectories—directly from the Pandas dataframe. The LLM (`llm.py`) ingests these raw metrics and translates them into non-technical, prescriptive executive summaries to explain exactly what the generated charts mean for the business.
* **Vanilla Frontend Interface:** A single-file HTML/JS/CSS frontend connects to the FastAPI backend. It handles CSV uploads, renders interactive Plotly JSON charts, manages persistent business rules, and provides the chat interface for the user's data queries.

---

## Elevating MyAnalyst



### Phase 1: Enterprise Infrastructure & Security (The Shift to Scale)

Your current architecture is perfect for a local machine or a single server, but it cannot handle thousands of concurrent enterprise users securely.

* **From Vanilla JS to a Modern Frontend:** Your single-file vanilla HTML/JS frontend without a build step is a bottleneck for complex state management. Rebuild the frontend using **React (Next.js)** or **Vue**. This allows for real-time WebSocket streaming of the agent's thought process (showing the user "Planning...", "Writing Python...", "Executing...", "Correcting Error..."), rich interactive dashboard grids, and collaborative workspaces.
* **From SQLite to Distributed Memory:** SQLite (`memory.py`) will lock up under concurrent commercial use. Migrate to **PostgreSQL**. Introduce a Vector Database (like Pinecone or pgvector) to store the business rules and data dictionarie
3) Automated Data Pipeline: Replace the manual ingest.py script with a webhook or cron job. This ensures new technical PDFs or wiki updates are automatically chunked and embedded without developer intervention.

4) Agentic Workflow Architecture: Upgrade the linear LangChain retrieval pipeline to a multi-agent system using LangGraph. This allows the system to route queries intelligently, trigger external APIs for real-time diagnostics, or execute multi-step reasoning before answering.
s as semantic embeddings. This allows the AI to recall complex company knowledge across millions of past queries.
* **From Docker SDK to MicroVMs:** Using the Docker SDK to spin up containers on the host machine is risky for a multi-tenant SaaS. If a user manages a container breakout, they compromise the whole server. You must migrate the execution sandbox to **Firecracker microVMs** (the technology behind AWS Lambda) or **gVisor**. This provides hardware-level isolation for untrusted LLM-generated code.

### Phase 2: Universal Data Connectivity (Beyond the CSV)

Commercial users do not want to download CSVs from their CRM just to upload them to your app. MyAnalyst needs to sit directly on top of their live data.

* **Database Integrations:** Build secure OAuth connectors to **Snowflake, Google BigQuery, PostgreSQL, and AWS S3**.
* **Multi-Table Agentic SQL:** Currently, the LangGraph Coder node relies strictly on pandas to analyze a single uploaded CSV. You must train the agent to write, execute, and self-correct **SQL queries** that join multiple tables across a company's data warehouse before bringing the aggregated result into pandas for ML/Forecasting.
* **Unstructured Data:** Allow users to upload PDFs (like financial reports or marketing PDFs) alongside their tabular data. The agent should be able to cross-reference text sentiment with numeric sales data.

### Phase 3: Multi-Agent "Swarm" Architecture (The AI Brain)

Right now, you have one LangGraph flow handling Q&A. A benchmark product requires a "Swarm" of specialized agents that talk to each other.

* **The Data Engineer Agent:** Specializes strictly in cleaning data, writing complex regex, and structuring joins.
* **The Statistician Agent:** Evaluates the Data Engineer's output, runs tests for stationarity/seasonality, and selects the exact mathematical parameters (like the Auto-ARIMA $p, d, q$ values).
* **The QA / Reviewer Agent:** A separate LLM node that *only* looks at the output of the Statistician and asks, "Does this answer actually make business sense?" before showing it to the user.
* **The Chief of Staff Agent:** The only agent the user talks to. It delegates tasks to the sub-agents and synthesizes their work into a final executive summary.

### Phase 4: Production MLOps (Actionable Outputs)

You just added an AutoML feature that runs `HistGradientBoosting` and explains the drivers. A world-class tool doesn't just explain the model; it deploys it.

* **One-Click API Deployment:** If a user builds a churn prediction model in MyAnalyst, add a feature that automatically packages that model using FastAPI and Docker, giving the user a live API endpoint they can plug directly into their company's website or CRM.
* **Continuous Monitoring:** The platform should periodically wake up, re-run the time-series forecasts on live database connections, and send the business owner a Slack/Email alert if real-world sales drop below the model's confidence intervals.


---
## UI ENHANCEMENTS

**DONE:**

1. Show answers as formatted text, not raw text. .answer-text currently shows the model's output as-is, so tables, bullet lists and bold text from the LLM come out as literal symbols. Converting it with a small Markdown library (marked plus DOMPurify, about 30 KB) would make answers look finished. Your citation pills would still run on the converted output. This is the biggest improvement per line of code.
2. Stream answers word by word. Several 2026 guides treat streaming as the baseline expectation for any LLM interface. Right now the user watches the three-dot "thinking" row and then the whole answer appears at once. Even without changing the backend, you can make the progress row more informative: show the real stages the agent goes through (routing → writing code → running → self-correcting, attempt 2) as a small checklist that fills in. You already return intent and attempts, so that's a natural place to start.
3. Restyle the Predictive Modeling card. It's the only card built with inline styles, so its <select> and loading text look out of place next to everything else. Give it the same glass input styling, a custom dropdown arrow, and a placeholder that looks like a chart outline while the model trains, instead of the "this may take up to 10 seconds" text.
4. Light theme and accent colour choice. Your colours are already defined as variables, so a light theme is mostly a second set of values. It also helps when someone shows the app on a projector.
5. Command palette (Ctrl/Cmd + K). Jump to a chart, ask a question, toggle Focus Mode or add a rule from one search box. Power users expect this now, and it's cheap to build.

**TO BE DONE:**

6. Add KPI tiles above the executive summary. Put 3–4 large-number cards across the top: rows, columns, missing values cleaned, and maybe the strongest correlation. Each would have a small sparkline or a change badge. This is the most recognisable "modern dashboard" pattern, and it breaks up the stack of text cards that the dashboard currently is.
7. Put interactive components inside chat answers. Rather than only text plus a chart, answers can include small built-in components: a sortable table for tabular results, and follow-up suggestion chips under each answer (you already have the starter-chip style). One developer reported that replacing a back-and-forth chat exchange with an in-chat form cut drop-off from 60% to 12% (a single anecdote, not a study).
8. Use placeholder outlines while loading. Show shimmering outline cards in the dashboard while files upload, instead of a single spinner. It feels faster and keeps the layout from jumping.
9. Add small animations that show something happened. A pulse on a chart cell when it finishes rendering, a short flash when a business rule is saved, and a "copied" check on a new copy-code button in the code viewer. The trend sources describe motion that signals state, not decoration, and these fit that.
10. Make the chart grid uneven. Give the first or most important chart a double-width cell instead of a strict 2-column grid. A mixed-size layout looks deliberate rather than templated.
11. Pin to dashboard. A pin button on any chart from a chat answer that adds it to the Exploratory charts grid. This connects the chat and the dashboard instead of keeping them separate.


---

**Backend Errors**

Problems and enhancements

Gives wrong answers

1. Outlier capping changes the real data. remediate_data (preprocessing.py) clips every number column
   to statistical bounds, and every downstream step uses the clipped values. For store_sales.csv that
   rewrote 507 Amount values (about 10%). So "Total Amount by Category", forecasts, models and chat
   answers all understate the real totals. Capping should be a flag or a view, not a rewrite of the
   data.
2. Missing values are filled with averages and then treated as real. Totals, counts and models can't
   tell real values from filled-in ones.
3. Predictive modeling loses date columns. main.py:321 reloads the cleaned CSV with a plain
   pd.read_csv, so dates come back as text. The model then treats each date as a separate category
   instead of extracting year, month and weekday.
4. Date detection only looks at column names. It only recognises names containing date/time/timestamp.
   Columns like Month, Period or Year are missed, and something like DateOfBirth would become the
   time axis.
5. Model accuracy can be overstated. The train/test split is random even for time-series data, so it
   trains on the future. Nothing guards against columns derived from the target. The target dropdown
   also offers ID and date columns.


Data safety and security

1.  No authentication. Anyone who can reach the server can read any workspace if they know its ID, and
    CORS allows any website.
2.  Nothing can be deleted. There are no delete endpoints for workspaces, files or business rules (rules can't be edited either), so data piles up forever.

Missing features

12. Reloading the page loses charts and code. Restored chat history is text only; charts and generated code from earlier answers are gone. Chart Q&A threads aren't saved at all.
13. No workspace switcher. "New analysis" makes the old workspace unreachable from the UI, though it's still in the database.
14. Answers arrive all at once. The steps shown while waiting are paced estimates; real streaming of the agent's steps would show what it's actually doing.
15. Retrieval over documents is basic.
    - It always returns the top 4 chunks, with no reranking or keyword search.
    - There's no OCR for scanned PDFs.
    - Word and text files have no page numbers to cite.
    - The embedding model loads at import time, which slows startup.
16. The multi-file executive summary is just per-file summaries glued together. It doesn't say anything that spans files.
17. EDA charts can't be changed. They're fixed at upload, with no "regenerate" or "add a chart like X" option.
18. The chart Q&A can't run new analysis. It only sees the chart's summarized data. A follow-up could hand off to the full agent.

Engineering hygiene

19. No tests or CI. Today's fixes were checked by hand.
20. No database migrations. create_all won't add new columns to existing tables.
21. The sandbox image has drifted from the server. It pins plotly 5.22 and pandas 2.2.2 while the server runs plotly 7, and it installs Prophet and pmdarima, which generated code never needs.




- Fix the graphs. Ensure they fit in the dashboard grid and are responsive to different screen sizes. Use Plotly's responsive layout features to make sure charts resize correctly on window resize events.
- 

