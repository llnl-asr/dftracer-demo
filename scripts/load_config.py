#!/usr/bin/env python3
"""Flatten config.yaml into shell `export DEMO_<SECTION>_<KEY>=...` lines.

Keys under the top-level `env` section are exported under their own names, and
each paths.<key> is also exported as DEMO_<KEY> (paths.pfs -> ${DEMO_PFS}).
Values may reference any variable defined above them in the file.
Empty or missing keys are not exported at all (paths.* fall back to DEFAULTS).

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
    if text in ("", "~", "null", "{}"):
        return None
    if text.startswith("[") and text.endswith("]"):
        return [_scalar(item) for item in text[1:-1].split(",") if item.strip()]
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


# Paths every step needs; used when config.yaml leaves them out or empty.
DEFAULTS = {
    "DEMO_PATHS_INSTALL": "${DEMO_ROOT}/install",
    "DEMO_PATHS_BUILD": "${DEMO_ROOT}/build",
    "DEMO_PATHS_DATA": "${DEMO_ROOT}/data",
    "DEMO_PATHS_TRACES": "${DEMO_ROOT}/traces",
    "DEMO_PATHS_RESULTS": "${DEMO_ROOT}/results",
    "DEMO_PATHS_RUNS": "${DEMO_ROOT}/runs",
}

# Runtime variables set by the scripts themselves, never by config.yaml.
RUNTIME = {"DEMO_ROOT", "DEMO_CONFIG", "DEMO_STEP_SCRIPT"}
# Names scripts/common.sh uses internally; paths.<key> never aliases onto them.
RESERVED = RUNTIME | {"DEMO_BENCH", "DEMO_STEP", "DEMO_JOB_ID", "DEMO_JOB_LOG", "DEMO_SBATCH_ARGS"}


def flatten(node, prefix):
    if prefix == "DEMO_ENV" and isinstance(node, dict):
        # Plain environment variables, exported under their own names.
        for key, value in node.items():
            yield str(key), value
    elif isinstance(node, dict):
        for key, value in node.items():
            yield from flatten(value, f"{prefix}_{re.sub(r'[^A-Za-z0-9]', '_', str(key)).upper()}")
    elif isinstance(node, list):
        yield prefix, " ".join(str(v) for v in node if v is not None and str(v) != "")
    else:
        yield prefix, node


def as_text(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return "1" if value else "0"
    return str(value)


def expand(value, env):
    """Expand ${VAR} against the environment plus keys defined above."""
    return re.sub(r"\$\{(\w+)\}", lambda m: env.get(m.group(1), m.group(0)), value)


def path_alias(name):
    """DEMO_PATHS_<KEY> is also exported as DEMO_<KEY> (e.g. ${DEMO_PFS})."""
    if name.startswith("DEMO_PATHS_"):
        alias = "DEMO_" + name[len("DEMO_PATHS_"):]
        if alias not in RESERVED:
            return alias
        print(f"load_config.py: paths.{alias[5:].lower()}: no ${{{alias}}} alias "
              f"(reserved name); use ${{{name}}}", file=sys.stderr)
    return None


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "config.yaml"
    entries = [(name, as_text(value)) for name, value in flatten(load(path), "DEMO")]

    # Default paths first, so any value may use them (${DEMO_DATA}, ...) even
    # when config.yaml leaves them out; then every key in file order.
    given = {name for name, text in entries if text}
    ordered = [(name, text) for name, text in DEFAULTS.items() if name not in given]
    ordered += [(name, text) for name, text in entries if text]

    env = dict(os.environ)
    values = {}
    for name, text in ordered:
        text = expand(text, env)
        for ref in re.findall(r"\$\{(DEMO_\w+)\}", text):
            print(f"load_config.py: {name}: ${{{ref}}} is not defined above it in {path}",
                  file=sys.stderr)
        # Empty or missing keys never get here: they stay unset, so callers
        # drop the corresponding flag instead of passing it blank.
        for var in (name, path_alias(name)):
            if var:
                values[var] = text
                env[var] = text

    # Clear config variables from an earlier activation that are gone now.
    for name in sorted(os.environ):
        if name.startswith("DEMO_") and name not in RUNTIME and name not in values:
            print(f"unset {name}")

    for name, value in values.items():
        print(f"export {name}={shlex.quote(value)}")


if __name__ == "__main__":
    main()
