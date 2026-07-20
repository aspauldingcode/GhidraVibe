"""LLM translation prompts (Malimite AIBackend parity) + optional OpenAI call."""

from __future__ import annotations

import json
import os
import re
import urllib.error
import urllib.request
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Malimite AIBackend DEFAULT_PROMPT / SUMMARIZE / VULNERABILITY
_DEFAULT_PROMPT = (
    "Translate the following decompiled functions into {language}. "
    "Return only the {language} code for these functions, preserving the method names "
    "and any global variables. "
    "You may adjust local variable names for readability, but do not add, remove, or "
    "modify any other methods or global definitions. "
    'Surround each translated function with "BEGIN_FUNCTION" at the beginning and '
    '"END_FUNCTION" at the end. '
    "Keep functions in the same order as they appear in the original code."
)

_SUMMARIZE_PROMPT = (
    "Provide a clear and concise summary of what these functions do. "
    "Focus on their purpose, key functionality, and any notable patterns. "
    "If you think this belongs to a known library, mention it. "
    "Format the response in markdown.\n\n"
)

_VULNERABILITY_PROMPT = (
    "Analyze these functions for potential security vulnerabilities and coding issues. "
    "Consider: memory safety, input validation, authentication bypasses, and common "
    "coding pitfalls. "
    "Ignore issues like readability, magic numbers, hardcoded values, and other minor "
    "issues since this is decompiled code. "
    "Don't provide recommendations for fixing these issues, just identify them and say "
    "how they could be exploited. "
    "Format the response in markdown with clear headers for each identified issue.\n\n"
)

PROMPTS: Dict[str, str] = {
    "auto_fix": _DEFAULT_PROMPT,
    "summarize": _SUMMARIZE_PROMPT,
    "find_vulnerabilities": _VULNERABILITY_PROMPT,
}

_ACTION_ALIASES = {
    "auto_fix": "auto_fix",
    "autofix": "auto_fix",
    "auto fix": "auto_fix",
    "summarize": "summarize",
    "find_vulnerabilities": "find_vulnerabilities",
    "find vulnerabilities": "find_vulnerabilities",
    "vulnerability": "find_vulnerabilities",
    "vulnerabilities": "find_vulnerabilities",
}

_BEGIN_END_RE = re.compile(
    r"BEGIN_FUNCTION\s*(.*?)\s*END_FUNCTION",
    re.DOTALL | re.IGNORECASE,
)

OPENAI_URL = "https://api.openai.com/v1/chat/completions"
DEFAULT_MODEL = os.environ.get("GHIDRA_VIBE_OPENAI_MODEL", "gpt-4o-mini")


def normalize_action(action: str) -> str:
    key = (action or "").strip().lower().replace("-", "_")
    if key not in _ACTION_ALIASES:
        # also accept spaces already lowercased
        key = key.replace("_", " ")
    mapped = _ACTION_ALIASES.get(key) or _ACTION_ALIASES.get(key.replace(" ", "_"))
    if not mapped:
        raise ValueError(
            f"Unknown action: {action!r}. Use auto_fix, summarize, or find_vulnerabilities."
        )
    return mapped


def build_prompt(action: str, code: str, language: str = "Swift") -> str:
    """Build a full prompt for ``auto_fix`` / ``summarize`` / ``find_vulnerabilities``."""
    action_key = normalize_action(action)
    if action_key == "auto_fix":
        lang = language if language else "Swift"
        if lang.lower() in ("objc", "obj-c", "objective_c"):
            lang = "Objective-C"
        header = PROMPTS["auto_fix"].format(language=lang)
    else:
        header = PROMPTS[action_key]
    return f"{header}\nHere are the functions to analyze:\n\n{code}"


def parse_begin_end_functions(text: str) -> List[str]:
    """Extract bodies between BEGIN_FUNCTION / END_FUNCTION markers."""
    if not text:
        return []
    return [m.group(1).strip() for m in _BEGIN_END_RE.finditer(text)]


def _resolve_api_key() -> Optional[str]:
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if key:
        return key
    key_file = os.environ.get("GHIDRA_VIBE_API_KEY_FILE", "").strip()
    if key_file:
        path = Path(key_file)
        if path.is_file():
            return path.read_text(encoding="utf-8").strip()
    return None


def _openai_chat(prompt: str, api_key: str, model: str = DEFAULT_MODEL) -> str:
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        OPENAI_URL,
        data=data,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"OpenAI HTTP {exc.code}: {err_body}") from exc

    if "error" in body:
        raise RuntimeError(f"OpenAI error: {body['error']}")

    choices = body.get("choices") or []
    if not choices:
        raise RuntimeError("OpenAI response missing choices")
    content = choices[0].get("message", {}).get("content") or ""
    # Strip fenced code blocks if present (Malimite parseOpenAIResponse)
    if "```" in content:
        start = content.find("```")
        nl = content.find("\n", start)
        end = content.rfind("```")
        if nl != -1 and end > nl:
            content = content[nl + 1 : end].strip()
    return content


def translate_local(
    action: str,
    code: str,
    language: str = "Swift",
) -> Tuple[str, Optional[List[str]]]:
    """Run translation/summary via OpenAI when keyed; else return prompt + Agent note.

    Returns ``(text, parsed_functions_or_None)``.
    """
    prompt = build_prompt(action, code, language=language)
    api_key = _resolve_api_key()
    if not api_key:
        note = (
            prompt
            + "\n\n---\n"
            + "No OPENAI_API_KEY or GHIDRA_VIBE_API_KEY_FILE set. "
            + "Paste this prompt into the GhidraVibe Agent / Cursor chat, "
            + "or set a key to call OpenAI chat completions from this CLI.\n"
        )
        return note, None

    response = _openai_chat(prompt, api_key)
    functions = parse_begin_end_functions(response)
    return response, functions or None
