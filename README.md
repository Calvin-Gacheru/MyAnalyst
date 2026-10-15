# MyAnalyst

Autonomous data analysis platform: deterministic pandas preprocessing feeds
a LangGraph agent that runs proactive EDA/forecasting and a self-correcting
Q&A loop, served over FastAPI, with a glassmorphic vanilla HTML/CSS/JS
frontend.

## Running it

```bash
pip install -r requirements.txt
export DEEPSEEK_API_KEY=<your DeepSeek API key>
export MYANALYST_LLM_MODEL=deepseek-chat
uvicorn main:app --reload --port 8000
```

Then open **http://localhost:8000/** — `main.py` mounts `frontend/index.html`
at `/` (after every API route, so nothing is shadowed), so the one command
serves both the API and the UI. The frontend also auto-detects that it's
being served from the same origin, so there's no setup step; the gear icon
in the top bar is only there for the rare case of serving the frontend from
somewhere else.

## Backend files

- `config.py` — environment-driven settings
- `schemas.py` — Pydantic API request/response models
- `memory.py` — SQLite persistence (datasets, business rules, chat history)
- `preprocessing.py` — Workflow steps 1–2: deterministic pandas heuristics
- `llm.py` — every Anthropic API call (data dictionary, summaries, plan/code/prescriptive generation)
- `sandbox.py` — `execute_code_in_docker`, currently a mocked local executor (see its docstring for the swap-in plan to a real container)
- `graph.py` — Workflow steps 3–4: the EDA/forecast LangGraph and the cyclic Q&A LangGraph
- `main.py` — FastAPI routes, wiring, and the static-file mount that serves the frontend

Note: `sandbox.py`'s `execute_code_in_docker` currently runs generated
scripts in-process inside a restricted namespace rather than inside an
actual Docker container. This was left as a clearly-marked placeholder per
the original spec — swap its body for a real container call before running
untrusted code against it in production.

## Frontend

`frontend/index.html` is a single self-contained file — no build step, no
dependencies to install. Normally you don't touch it directly: it's served
automatically by the backend at `/` (see "Running it" above). It can also
be opened standalone (double-click, or any static file server) if you ever
want to point it at a backend running elsewhere — use the gear icon to set
that backend's address.

It talks to:

- `POST /datasets/upload` — CSV upload → cleaning log, data dictionary, charts, executive summary
- `GET/POST /datasets/{id}/business-rules` — persistent rules the Q&A planner respects
- `POST /datasets/{id}/qa` — ask a question; shows the generated code, retry count, and prescriptive answer
- `GET /datasets/{id}/chat-history`

Because it's a plain static file making cross-origin requests, `main.py`
already enables permissive CORS (`allow_origins=["*"]`) so this works out
of the box for local development. Tighten `allow_origins` to the frontend's
real origin before deploying anywhere beyond your own machine.



---

## How to run 

4) Build and Verify the sandbox Docker image (if you haven't already):
```bash
docker build -t myanalyst-sandbox:latest -f Dockerfile.sandbox .
```

5) Run the backend FastAPI server:
```bash
uvicorn main:app --reload --port 8000
```