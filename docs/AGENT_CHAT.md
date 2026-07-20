# Agent chat sidebar

Xcode-style **trailing Agent column** on CodeBrowser (toolbar `sidebar.trailing` /
`ghidra.vibe.toolbar.agent_sidebar`). On by default with a Welcome screen; opt out
via `GHIDRA_VIBE_AI=0`, Settings, or **Opt out of Agent**.

## Default behavior

- Welcome explains in-app agent vs Cursor + MCP workflow.
- Default LLM backend: **Metal Ollama** via OpenAI-compatible
  `POST {base}/v1/chat/completions` (same contract as the dendritic `chat` CLI).
- **Mixture of Experts (MoE)** — routes each turn to a local expert model by task
  (general / code / decompile / apple / plan). Optional proprietary API escalation
  when a key file is set and escalation is enabled.
- Base URL resolution:
  `GHIDRA_VIBE_AI_BASE_URL` → `AI_LOCAL_BASE_URL` → `OLLAMA_HOST` →
  `http://127.0.0.1:11434`
- Default model:
  `GHIDRA_VIBE_AI_MODEL` → `AI_LOCAL_DEFAULT_MODEL` → `qwen2.5-coder:3b`
- Expert overrides: `GHIDRA_VIBE_AI_MODEL_CODE`, `_DECOMPILE`, `_APPLE`, `_PLAN`
- Model picker: `GET {base}/api/tags`
- **ANEMLL / ANE ranking is a stub** (`GHIDRA_VIBE_AI_BACKEND=anemll`).
- **No cloud/API access is shipped.** Proprietary API is opt-in only via key file.

## Opt into API (user-specified only)

1. **Nix** (path to a key file — never a raw key string in config):

```nix
programs.ghidra-vibe.agent.baseUrl = "http://127.0.0.1:11434";
programs.ghidra-vibe.agent.model = "qwen2.5-coder:3b";
programs.ghidra-vibe.agent.apiKeyFile = "/run/agenix/openai_api_key";
programs.ghidra-vibe.agent.moe.allowCloudEscalation = true;
programs.ghidra-vibe.agent.moe.codeModel = "qwen2.5-coder:7b";
programs.ghidra-vibe.agent.moe.decompileModel = "qwen2.5-coder:7b";
```

2. **GUI Settings** — base URL, default model, MoE expert models, “Allow API escalation”,
   API key file path.

Keys must never be committed or baked into the nix store.

## Tool loop

Each send:

1. Build a **JSpace discovery pack** (`rag_discover`)
2. **MoE route** — pick expert model (and optional cloud escalation)
3. Call the LLM with a small typed tool set
4. Execute tools (GuiControl + analysis `:8089` + vibe `:8092` + in-process engine writes)
5. On local failure with escalation on → retry proprietary API
6. Reply in the transcript (footer shows `moe=role:model`)

Tools include: `gui_*`, `list_functions`, `decompile_function`, `get_xrefs`,
`rename_function`, `set_comment`, `rag_*`, `improve_decompile`, `autonomous_re`.

If the model fails JSON tool schema, the UI falls back to a rename-table parse and
**Apply** pending edits.

## Write path

- In-process engine: `rename_function`, `set_plate_comment`, `set_eol_comment`
- Headless script: `ghidra_scripts/RenameFunctionVibe.java`
- GuiControl: `POST /agent/rename`, `/agent/comment`, `/agent/send`, `/agent/status`,
  `/agent/playbook`, `/agent/improve_decompile`
- Cursor bridge: `bridge_mcp_gui.py` → `agent_*` tools

**Apply** refreshes Functions + Decompile.

## Autonomous RE

Toolbar/chat **Autonomous RE** (or `POST /agent/playbook`):

1. Index JSpace if empty
2. Rank interesting functions (entry, `FUN_`/`sub_`, ObjC methods)
3. Budgeted `improve_decompile` (renames + plate comments)
4. Session report in Agent transcript + Console

Status-bar Task Monitor is driven while the playbook runs.

## Tests

- `gui-tests/smoke-agent-welcome.sh` — opt-out preferences
- `gui-tests/smoke-agent-api-config.sh` — key-file opt-in (no network)
- `gui-tests/smoke-agent-sidebar.sh` — GuiControl `/agent/status` + optional Ollama
- `gui-tests/smoke-agent-npu.sh` — Ollama `/api/tags` probe (ANEMLL stub note)
- Live chat: start Ollama, open Agent sidebar, send a message
