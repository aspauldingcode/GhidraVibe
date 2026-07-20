"""JSpace — RE-oriented hybrid RAG (FTS5 + hashing vectors) for GhidraVibe agents."""

from .embed import expand_re_query, hashing_embed
from .retrieve import discovery_context, search
from .store import JSpaceStore

__all__ = [
    "JSpaceStore",
    "hashing_embed",
    "expand_re_query",
    "search",
    "discovery_context",
]
