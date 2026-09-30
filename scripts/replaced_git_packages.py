#!/usr/bin/env python3
"""Print the `git+` pip specs whose repository is no longer what is installed.

Usage: replaced_git_packages.py SPEC [SPEC ...]

pip records the source of a direct-URL install in the distribution's
direct_url.json. A git spec counts as replaced when no installed distribution
was installed from that repository (e.g. a dependency pulled the PyPI release
over it).
"""

import json
import sys
from importlib import metadata


def repo_of(url):
    url = url[len("git+"):] if url.startswith("git+") else url
    url = url.split("#", 1)[0]
    if "@" in url.rsplit("/", 1)[-1]:
        url = url.rsplit("@", 1)[0]
    return url.rstrip("/").removesuffix(".git").lower()


def installed_repos():
    repos = set()
    for dist in metadata.distributions():
        text = dist.read_text("direct_url.json")
        if text:
            info = json.loads(text)
            if "vcs_info" in info:
                repos.add(repo_of(info["url"]))
    return repos


def main():
    repos = installed_repos()
    for spec in sys.argv[1:]:
        if spec.startswith("git+") and repo_of(spec) not in repos:
            print(spec)


if __name__ == "__main__":
    main()
