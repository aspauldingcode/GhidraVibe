# Agent chat sidebar

Xcode-style **trailing Agent column** on CodeBrowser (toolbar `sidebar.trailing` /
`ghidra.vibe.toolbar.agent_sidebar`). Agent is **not** a modular Window / dock
provider — it only toggles as the right sidebar (Window → Show/Hide Agent).
The leading **Modules** sidebar (`sidebar.leading`) lists dockable providers.
On by default with a Welcome screen; opt out via `GHIDRA_VIBE_AI=0`, Settings,
or **Opt out of Agent**.

**GhidraVibe never ships LLM weights.** Configure cloud APIs or point at local
runtimes you already have (Ollama / llama.cpp).

## Quick setup (GUI)

Open Agent → gear (**Agent Setup**) or Welcome → **Set up models…**:

1. Pick a **provider** — Ollama, llama.cpp (GGUF), OpenAI, Anthropic, Google Gemini,
   or **OpenAI-compatible** (OpenRouter, Groq, DeepSeek, Mistral, Together, …).
2. Pick a **model** (live list when the backend is up; otherwise suggested ids).
3. For proprietary APIs: set **API key file** path (never paste keys into Nix).
4. For local GGUF: **drop `.gguf` / `.ccp`** onto the Setup panel (copied into
   `~/Library/Application Support/GhidraVibe/models`). Serve with
   `llama-server -m <file.gguf> --port 8080`.

## Providers

| Provider | Transport | Notes |
|----------|-----------|--------|
| Ollama | OpenAI-compat `:11434` | Default; Metal |
| llama.cpp | OpenAI-compat `:8080` | User GGUF drops only |
| OpenAI | `/v1/chat/completions` | Bearer key file |
| Anthropic | `/v1/messages` | `x-api-key` |
| Google Gemini | `generateContent` | API key query |
| OpenAI-compatible | `/v1/chat/completions` | Any minor gateway |

Env: `GHIDRA_VIBE_AI_PROVIDER`, `GHIDRA_VIBE_AI_BASE_URL`, `GHIDRA_VIBE_AI_MODEL`,
`GHIDRA_VIBE_API_KEY_FILE`, `GHIDRA_VIBE_AI_MODELS_DIR`,
`GHIDRA_VIBE_AI_CLOUD_PROVIDER`.

## Nix (declarative, no weights in store)

Model **names** for testing live in [`nix/agent/models.nix`](../nix/agent/models.nix)
(matching Ollama tags on the development machine). Pull them with:

```bash
nix run .#ghidra-vibe-agent-ensure-models
```

Home Manager example:

```nix
programs.ghidra-vibe = {
  enable = true;
  agent = {
    provider = "ollama";
    baseUrl = "http://127.0.0.1:11434";
    model = "qwen2.5-coder:3b";
    # modelsDir = "${config.home.homeDirectory}/Library/Application Support/GhidraVibe/models";
    # apiKeyFile = "/run/agenix/openai_api_key"; # proprietary opt-in
    cloudProvider = "openai";
    ollama.ensureModels = [
      "qwen2.5-coder:3b"
      "qwen2.5-coder:7b"
      "llama3.2:3b"
      "gemma3:4b"
    ];
    moe = {
      enable = true;
      allowCloudEscalation = false;
      codeModel = "qwen2.5-coder:7b";
      decompileModel = "qwen2.5-coder:7b";
    };
  };
};
```

Keys must never be committed or baked into the nix store.

## Mixture of Experts

Optional task routing (general / code / decompile / apple / plan) across local
model tags. Cloud escalation retries with `cloudProvider` when a key file is set.

## System pre-prompt

Every LLM turn injects [`AgentSystemPrompt`](../macos/GhidraVibe/Sources/GhidraVibe/AgentSystemPrompt.swift)
via `AgentTools.systemPrompt(for:)` — environment (engine / windows / MCP ports), MoE role,
tool catalog, GuiControl map, full RE playbook, and research rules. Role-specific focus is
appended for `general` / `code` / `decompile` / `apple` / `plan`.

## Modes (Cursor-style)

Header menu next to History picks the interaction mode (persisted per chat session):

| Mode | Behavior |
|------|----------|
| **Ask** | Answer only — no tools |
| **Agent** | Full RE tool loop (default) |
| **Plan** | Research tools + emit a fenced `plan` artifact; writes gated until **Build** |
| **Debug** | Debugger / listing–focused tool allowlist |
| **Multitask** | Same tools as Agent + labeled send-queue lanes (`primary` / `background`) |

**Build** on the plan card queues Agent turns for each pending step and switches to Agent mode.

Header also has a compact **model picker** (recent list + deep-link to Agent Setup).

## Theming (Ghidra Theme)

**GhidraVibe → Settings… (⌘,)** → **Appearance** sets the global **Ghidra Theme**
(Base16 palettes via [TintedThemingSwift](https://github.com/aspauldingcode/TintedThemingSwift)).
Persisted as `ghidra.vibe.theme.ghidra` (legacy `ghidra.vibe.theme.base16` still migrates).

The theme owns **all** app backgrounds and foregrounds: window fills, Project Window,
CodeBrowser providers (Listing / Decompiler / Console / Bytes / trees / lists), Help,
Agent, Function Graph, status bar, editors, and syntax colors. Use `Color.vibeForeground`
/ `Color.vibeContent` (and `vibeDocumentPane` / `vibeThemedList` / `vibeThemedEditor`) —
not system `.primary` / `.secondary`. **Edit → Theme** also opens Settings.

## Message rendering

Assistant/user bubbles use **Textual** markdown, syntax-highlighted codeblocks,
`@` mention chips, and optional diagrams:

- Fenced ` ```dot` / ` ```graphviz` / ` ```mermaid` — rasterize via local `dot` / `mmdc` when installed; otherwise highlighted source + **Retry**
- Fenced ` ```cfg` — embeds the current Function Graph (or prompts refresh)

## Composer (iMessage-style)

- Capsule text field with **+** (attach / @ mention) and circular send
- `@` tokens render as accent chips in the composer while editing (plain paste)
- Attachments: paperclip chips; text files are inlined into the next turn
- **Context radial** (top-right of composer): estimated tokens vs model window;
  click to renew/summarize. Auto-renew runs near **75%** (keeps a rolling summary
  + last ~8 turns; up to ~24 live turns are sent with each request), similar to
  Cursor’s context ring. When a summary exists, the composer shows a memory chip.
- **Reply**: every bubble has **Reply** (button + context menu). The composer shows
  a quote chip; the LLM receives the quoted message with your new text. Replies
  persist on the bubble and in chat history.
- **Return** sends · **Shift+Return** newline · **⌘Return** interrupts in-flight then sends next
- Queue bar: per-item remove; Multitask shows lane labels

## History (project-scoped)

Agent conversations are saved under
`~/Library/Application Support/GhidraVibe/agent-chats/` (override with
`GHIDRA_VIBE_AGENT_CHATS_DIR`).

- Each chat is keyed to the open **Ghidra project** (`.gpr` path)
- Switching projects saves the current chat and restores that project’s active session
- Agent header **History** menu: New Chat, chats for this project, chats from recent projects
- Workspace picker recent-project rows show a one-line preview of the latest Agent chat
- Context renew archives dropped turns into the same session file (still mentionable)

## `@` mentions (Cursor-style)

Type `@` in the Agent composer (or click the **@** button) to attach context:

| Category | Examples |
|----------|----------|
| Functions | `@Functions:entry` |
| Providers | `@Providers:decompiler` |
| Program & Selection | `@Program`, `@Selection` |
| Classes | `@Classes:NSView` |
| Past Chats | `@PastChats:3`, `@PastChats:Session:<uuid>` |
| Docs | `@Docs:re-playbook`, `@Docs:dsc` |

`@PastChats:N` is a turn in the **current** transcript; `@PastChats:Session:…` pulls a
saved conversation (this project or another recent project).

Tokens stay visible in the bubble; the LLM turn also gets a **Mentions** appendix with
expanded context (see [`AgentMentions.swift`](../macos/GhidraVibe/Sources/GhidraVibe/AgentMentions.swift)).

## Tool loop

Each send:

1. Build a **JSpace discovery pack** (`rag_discover`) — skipped for short chitchat
2. **MoE route** — pick expert model (and optional cloud escalation)
3. Call the LLM with the system brief + typed tool set (incl. `web_search`)
4. Execute tools (GuiControl + analysis `:8089` + vibe `:8092` + in-process engine writes + web research)
5. On local failure with escalation on → retry proprietary API
6. Reply in the transcript (footer shows `moe=role:model`)

Casual greetings omit tools so tiny local models do not dump raw tool JSON.

## Tool permissions (Cursor-style)

**Agent Setup → Tool permissions** controls how tools run:

| Default | Behavior |
|---------|----------|
| **Ask every time** | Approve each tool call |
| **Allow reads · ask writes** | Reads/navigate auto; writes + network ask (default) |
| **Allow for session** | No prompts until quit (Always Deny still applies) |
| **Always allow all** | Persist Always Allow for every tool |

When a tool needs approval, the Agent sidebar shows **Allow once / Session / Always / Deny**.

**Sandbox tool calls** (default on):

- `web_search` only keeps DuckDuckGo / Wikipedia hosts
- Dangerous `gui_action` ids (`auto_analyze`, `save_program`, imports, …) count as **writes**

**Reset tool permissions** clears Always Allow / session allows and restores the default profile + sandbox.

GuiControl (tests / automation):

- `GET /agent/permissions`
- `POST /agent/permissions` `{ "profile": "askWrites", "sandbox": true }`
- `POST /agent/permissions/reset`
- `POST /agent/tool` `{ "name": "list_functions", "args": {}, "auto_approve": true }`

## Tests

- `gui-tests/smoke-agent-welcome.sh` — opt-out preferences + theme defaults key
- `gui-tests/smoke-agent-api-config.sh` — key-file opt-in (no network)
- `gui-tests/smoke-agent-tool-permissions.sh` — permission gate + tool call + reset
- `gui-tests/smoke-agent-sidebar.sh` — GuiControl `/agent/status` (mode/theme) + optional Ollama
- `gui-tests/smoke-agent-npu.sh` — Ollama `/api/tags` probe (ANEMLL stub note)
- Live chat: configure Agent Setup, send a message
