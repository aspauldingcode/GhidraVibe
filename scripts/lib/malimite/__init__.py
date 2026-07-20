"""malimite — Apple IPA/bundle RE helpers for GhidraVibe.

Reimplements analysis logic inspired by LaurieWired/Malimite (Apache-2.0):
library skip lists, resource harvesting, Swift demangling, SQLite project DB,
and LLM translation prompts. Does not copy Malimite's proprietary Swing UI.

https://github.com/LaurieWired/Malimite
"""

__version__ = "0.1.0"
__all__ = [
    "__version__",
    "libraries",
    "plist",
    "resources",
    "demangle_swift",
    "db",
    "ai",
    "pipeline",
]
