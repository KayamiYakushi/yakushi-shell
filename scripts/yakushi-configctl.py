#!/usr/bin/env python3
"""The Yakushi config file from the command line.

Commands:
    init            Create the config (carrying over old settings) if it is
                    missing, upgrade an older one. Safe to run any time.
    path            Print where the config lives.
    get [section]   Print the config, or one section, as JSON.

The file itself is described in yakushi_config.py. Runs only when called.
"""
from __future__ import annotations

import json
import sys

import yakushi_config as config


def main() -> None:
    args = sys.argv[1:]

    if args == ["init"]:
        config.load()
    elif args == ["path"]:
        print(config.FILE)
    elif args[:1] == ["get"] and len(args) <= 2:
        try:
            data = config.section(args[1]) if len(args) == 2 else config.load()
        except KeyError:
            raise SystemExit(f"Unknown section: {args[1]} (one of {', '.join(config.SECTIONS)})")
        print(json.dumps(data, indent=2, ensure_ascii=False))
    else:
        raise SystemExit("Usage: yakushi-configctl.py init | path | get [section]")


if __name__ == "__main__":
    main()
