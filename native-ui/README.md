# Shared native UI contracts

| Path | Role |
| --- | --- |
| `layout/CodeBrowser.tool.json` | Normalized from stock Ghidra `CodeBrowser.tool` |
| `layout/CodeBrowser.tool.xml` | Upstream XML extract |
| `menus/actions.json` | Menu / action catalog (macOS + GTK) |
| `a11y/catalog.json` | Stable ids, labels, hints (tooltips) for agent-device |
| `icons/` | Official Ghidra dragon (`AppIcon.icns`, PNG sizes) |

Both shells load these contracts; do not fork ids per platform.
