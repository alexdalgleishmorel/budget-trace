"""HTTP route handlers, one module per resource. Each registers an APIRouter
that `main.py` mounts. Business logic lives in the tool functions inside
`mcp_server.py` (or `services/` modules) — routes are thin wrappers."""
