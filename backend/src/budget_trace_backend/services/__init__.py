"""Business logic shared between REST routes and MCP tools.

Why split this out: a write operation like "create category" is the same
underlying SQL whether it's invoked by `POST /categories` (REST) or by the
chat AI calling `create_category` over MCP. Both call into here.

Read tools still live in `mcp_server.py` — they're already the canonical
form. Only writes get a service layer because they have the most overlap.
"""
