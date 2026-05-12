"""Curated palette keys for category tile colors.

The actual color values live in the frontend (`theme/app_theme.dart`), which
resolves each key to a light- or dark-mode hex based on the active theme. The
backend only stores and validates the key string.
"""

from __future__ import annotations

# Ordered for stable display; backend code shouldn't rely on order, but keeping
# it consistent with the frontend picker makes debugging easier.
CATEGORY_PALETTE_KEYS: tuple[str, ...] = (
    "sage",
    "moss",
    "olive",
    "ochre",
    "sand",
    "cream",
    "clay",
    "rose",
    "plum",
    "lavender",
    "sky",
    "teal",
    "stone",
    "graphite",
)

_VALID = frozenset(CATEGORY_PALETTE_KEYS)

DEFAULT_CATEGORY_COLOR = "stone"


def is_valid_color(key: str) -> bool:
    return key in _VALID
