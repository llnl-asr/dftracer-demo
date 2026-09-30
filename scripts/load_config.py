#!/usr/bin/env python3
"""Flatten config.yaml into shell `export DEMO_<SECTION>_<KEY>=...` lines.

Keys under the top-level `env` section are exported under their own names.

Usage: eval "$(python3 scripts/load_config.py config.yaml)"

Uses PyYAML when available; otherwise falls back to a minimal parser that
understands the subset used by config.yaml (nested mappings, block lists,
scalars, comments). This lets activate_env.sh read the module list *before*
any module or virtual environment is loaded.
"""

import os
import re
import shlex
import sys


def _scalar(text):
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "'\"":
        return text[1:-1]
    if text.lower() in ("true", "false"):
        return text.lower() == "true"
    return text


def _strip_comment(line):
    out, quote = [], None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "'\"":
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1].isspace()):
            break
        out.append(ch)
    return "".join(out).rstrip()


def _mini_yaml(text):
    lines = []
    for raw in text.splitlines():
        line = _strip_comment(raw)
        if line.strip():
            lines.append((len(line) - len(line.lstrip()), line.strip()))

    def parse(i, indent):
        if lines[i][1].startswith("- "):
            items = []
            while i < len(lines) and lines[i][0] == indent and lines[i][1].startswith("- "):
                items.append(_scalar(lines[i][1][2:]))
                i += 1
            return items, i
        node = {}
        while i < len(lines) and lines[i][0] == indent:
            key, _, value = lines[i][1].partition(":")
            i += 1
            if value.strip():
                node[key.strip()] = _scalar(value)
            elif i < len(lines) and lines[i][0] > indent:
                node[key.strip()], i = parse(i, lines[i][0])
            else:
                node[key.strip()] = ""
        return node, i

    return parse(0, lines[0][0])[0] if lines else {}


def load(path):
    with open(path) as f:
        text = f.read()
    try:
        import yaml

        return yaml.safe_load(text) or {}
    except ImportError:
        return _mini_yaml(text)


def flatten(node, prefix):
    if prefix == "DEMO_ENV" and isinstance(node, dict):
        # Plain environment variables, exported under their own names.
        for key, value in node.items():
            yield str(key), "" if value is None else str(value)
    elif isinstance(node, dict):
        for key, value in node.items():
            yield from flatten(value, f"{prefix}_{re.sub(r'[^A-Za-z0-9]', '_', str(key)).upper()}")
    elif isinstance(node, list):
        yield prefix, " ".join("" if v is None else str(v) for v in node)
    elif isinstance(node, bool):
        yield prefix, "1" if node else "0"
    else:
        yield prefix, "" if node is None else str(node)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "config.yaml"
    env = dict(os.environ)
    for name, value in flatten(load(path), "DEMO"):
        # Expand ${VAR} against the environment plus keys already emitted.
        value = re.sub(r"\$\{(\w+)\}", lambda m: env.get(m.group(1), m.group(0)), value)
        env[name] = value
        print(f"export {name}={shlex.quote(value)}")


if __name__ == "__main__":
    main()
