# MyAnalyst

Autonomous multi-modal analysis workspace. Upload tabular data (CSV/XLSX) and documents (PDF/DOCX/TXT) into one workspace: deterministic pandas preprocessing feeds a LangGraph agent that runs proactive EDA/forecasting, a self-correcting Q&A loop executed in a network-isolated Docker sandbox, and pgvector-backed RAG over the documents. Served over FastAPI with a glassmorphic vanilla HTML/CSS/JS frontend.

## Backend files

- `config.py` — environment-driven settings
- `schemas.py` — Pydantic API request/response models
- `memory.py` — PostgreSQL + pgvector persistence via SQLAlchemy (workspaces, workspace files, document chunks, business rules, chat history)
- `preprocessing.py` — deterministic pandas cleaning heuristics
- `rag.py` — document parsing, chunking, local `all-MiniLM-L6-v2` embeddings, and pgvector semantic search
- `llm.py` — every DeepSeek call (data dictionary, summaries, intent routing, plan/code/prescriptive generation, RAG synthesis)
- `sandbox.py` — `execute_code_in_docker`: runs generated pandas code in a network-isolated, non-root, resource-limited container with every workspace dataset mounted read-only
- `graph.py` — the EDA/forecast LangGraph and the routed Q&A LangGraph (see below)
- `modeling.py` — AutoML predictive modeling
- `forecasting.py` — automatic time-series forecasting
- `main.py` — FastAPI routes, wiring, and the static-file mount that serves the frontend

### The Q&A graph

```
START -> route_intent -+-> plan -> code -> execute -+-> summarize -> END      (quant)
                       |             ^              +-> code (retry)
                       |             |              +-> give_up -> END
                       +-> rag_retrieve -+-> rag_synthesize -> END           (doc)
                       |                 +-> plan ...                        (hybrid)
                       +-> no_data -> END                                    (empty workspace)
```

The router only asks the LLM to classify when the workspace holds both datasets and documents; otherwise the track is chosen from the file types present. The hybrid track retrieves document excerpts first and hands them to the quant planner, so answers can compare computed numbers against targets or policies in the documents, with citations.

## Frontend

`frontend/` (`index.html`, `style.css`, `script.js`) has no build step and no dependencies. It is served automatically by the backend at `/`, and auto-detects that the API lives at the same origin. The gear icon in the top bar is only for pointing a standalone copy at a backend running elsewhere.

It talks to:

- `POST /workspaces/{id}/files` — upload one or more files (`id` = `new` creates a workspace); returns the full workspace state
- `GET /workspaces/{id}` — full workspace state (files, charts, dictionary, cleaning log, summary)
- `GET/POST /workspaces/{id}/business-rules` — persistent rules the Q&A planner respects
- `POST /workspaces/{id}/qa` — ask a question; returns the answer, track used, generated code, retry count, and source citations
- `GET /workspaces/{id}/chat-history?session_id=…`
- `POST /workspaces/{id}/predict` — AutoML on a target column

`main.py` enables permissive CORS (`allow_origins=["*"]`) for local development. Tighten it to the frontend's real origin before deploying beyond your own machine.

---

## How to run

### Prerequisites

- Python 3.11 and [uv](https://docs.astral.sh/uv/)
- Docker (with the daemon running and your user able to run `docker` without sudo)
- A DeepSeek API key

### 1. Configure environment variables

Create a `.env` file in the project root:

```bash
DEEPSEEK_API_KEY=<your DeepSeek API key>
MYANALYST_LLM_MODEL=deepseek-chat
# Optional — this is the default and matches docker-compose.yml:
# DATABASE_URL=postgresql://postgres:postgres@localhost:5432/myanalyst
```

A plain `postgresql://` URL is fine; `config.py` switches it to the installed psycopg (v3) driver.

### 2. Install Python dependencies

```bash
uv sync
```

Without uv: `pip install -r requirements.txt` (it mirrors the dependencies in `pyproject.toml`; regenerate it when those change).

The first backend start downloads the `all-MiniLM-L6-v2` embedding weights (~90 MB) once.

### 3. Start PostgreSQL + pgvector

```bash
docker compose up -d                              # starts the myanalyst_db container on port 5432
docker exec myanalyst_db pg_isready -U postgres   # wait until it reports "accepting connections"
```

Tables and the `vector` extension are created automatically when the backend starts.

### 4. Build the code-execution sandbox image

```bash
docker build -t myanalyst-sandbox:latest -f Dockerfile.sandbox .
```

Only needed once (and again after editing `Dockerfile.sandbox`). The backend starts a short-lived container from this image for every Q&A code run.

### 5. Run the backend server

```bash
uv run uvicorn main:app --reload --port 8000
```

Then open **http://localhost:8000/** for the UI, or **http://localhost:8000/docs** for the interactive API docs. `GET /health` returns `{"status": "ok"}` when the server is up.

### Useful Docker commands

```bash
docker compose ps                     # is the database running?
docker compose logs -f postgres_db    # database logs
docker compose stop                   # stop the database (data is kept)
docker compose down                   # remove the container (data is kept in the pgdata volume)
docker compose down -v                # remove the container AND wipe all workspace data
docker exec -it myanalyst_db psql -U postgres -d myanalyst   # open a SQL shell
docker images myanalyst-sandbox       # confirm the sandbox image exists
```

### Troubleshooting

- **`connection refused` on startup** — the database isn't running; run step 3.
- **`Docker image 'myanalyst-sandbox:latest' not found`** in a Q&A answer — run step 4.
- **`Unable to connect to Docker daemon`** — start Docker, and make sure your user is in the `docker` group.
- **`DEEPSEEK_API_KEY is not set`** — check the `.env` file from step 1.
