# Architecture

## The stack

```
┌────────────────┐   POST /chat    ┌────────────────────────┐
│  Flutter app   │ ───────────────▶│  Chat orchestrator     │
│  (Insights tab)│ ◀───────────────│  (FastAPI)             │
└────────────────┘   {text, chart?}└──┬─────────────────────┘
                                      │ Anthropic Messages API
                                      │ (tools = MCP tools + present_to_user)
                                      ▼
                              ┌────────────────────┐
                              │ Anthropic Claude   │
                              └──┬─────────────────┘
                                 │ tool calls
                                 ▼
                              ┌────────────────────┐
                              │ Tool dispatcher    │
                              │ (in-process)       │
                              └──┬─────────────────┘
                                 │ sqlite3
                                 ▼
                              ┌────────────────────┐
                              │ SQLite DB          │
                              │ (seeded, 12 mo)    │
                              └────────────────────┘
```

The MCP server (`backend/src/budget_trace_backend/mcp_server.py`) is *both* a standalone stdio server (for Claude Desktop or any other MCP client) and an in-process function dictionary the orchestrator dispatches against directly. Same Python functions back both code paths — one source of truth.

## One round-trip

When the user sends "what does my grocery spending look like the past 6 months?" from the Insights tab:

1. `InsightsScreen._submit` ([frontend/lib/screens/insights_screen.dart](../frontend/lib/screens/insights_screen.dart)) appends a user `ChatMessage` and a pending assistant `ChatMessage`, then calls `ChatClient.sendChat(history)`.
2. `ChatClient` ([frontend/lib/services/chat_client.dart](../frontend/lib/services/chat_client.dart)) POSTs `{messages: [...]}` to `${API_BASE_URL}/chat`. `API_BASE_URL` is set via `--dart-define`.
3. FastAPI's `chat` handler ([backend/src/budget_trace_backend/main.py](../backend/src/budget_trace_backend/main.py)) calls `run_chat`.
4. `run_chat` ([backend/src/budget_trace_backend/chat.py](../backend/src/budget_trace_backend/chat.py)):
   1. Builds tool schemas from the Python signatures of `TOOL_FUNCTIONS` plus the inline `present_to_user` schema.
   2. Sends the conversation to the Anthropic Messages API along with the tool list and the system prompt.
   3. Loops on `tool_use` blocks: each call to `aggregate_spending`, `list_categories`, etc. is dispatched against the in-process function, the result is appended as a `tool_result`, and the loop iterates.
   4. When Claude calls `present_to_user(text, chart?)`, those args become the HTTP response body. The chart (if present) is parsed into a `ChartSpec` model and serialised to JSON.
5. Flutter receives `{text, chart?}`. The pending assistant message is replaced with the resolved one. If the message has a chart, `_latestChart` recomputes and the sticky chart panel above the chat re-renders.

The conversation is fully stateless on the backend — every turn the full history is sent up. This matches the Anthropic Messages API shape and keeps server-side simplicity high.

## Why two tool surfaces

- **MCP data tools** are *portable read access*. They survive being pointed at from Claude Desktop, scripts, or any other MCP client. Their schema *is* the data API.
- `present_to_user` is *output formatting* for this specific app's chat UI. Putting it on the MCP server would conflate "read data" with "render in this app's chat" — it's not portable, so it lives only inside the orchestrator.

See [insights-ai.md](insights-ai.md) for the full prompt + tool list.

## Out of scope (for now)

- **Streaming.** The orchestrator waits for the full Anthropic response before replying. Streaming responses (incl. progressive chart-spec arrival) is a future enhancement.
- **Auto-categorisation.** Imports always insert with `category_id = NULL`. Users assign via the chip dropdown. Learned merchant→category memory and AI-assisted categorisation are explicit follow-ups, not part of this iteration.
- **Auth, multi-user, deployment.** Local dev only — single hardcoded user (id=1).
- **Async import jobs.** CSV finishes in the POST; AI parsing is fast enough to do the same. The `job_id` field is informational; if uploads ever need backgrounding, a polling endpoint slots in.
