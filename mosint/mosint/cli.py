"""Command-line interface for Mosint."""

from __future__ import annotations

import argparse
import sys

from . import __version__
from .config import load_config
from .modules import ALL_MODULES, InvalidEmailError, parse_email
from .orchestrator import Scanner, select_modules
from .reporting import render_json, render_text

USE_NOTICE = (
    "Mosint is for AUTHORISED use only (your own accounts, permitted exposure "
    "checks, sanctioned engagements). Respect each provider's terms of service "
    "and all applicable law."
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mosint",
        description="An all-in-one automated email OSINT framework. " + USE_NOTICE,
    )
    parser.add_argument("email", nargs="?", help="Target email address to investigate.")
    parser.add_argument(
        "-c",
        "--config",
        help="Path to a TOML config file (default: ./config.toml if present).",
    )
    parser.add_argument(
        "-m",
        "--modules",
        help="Comma-separated modules to run (default: all). "
        f"Available: {', '.join(cls.name for cls in ALL_MODULES)}.",
    )
    parser.add_argument(
        "-o",
        "--output",
        choices=["text", "json"],
        default="text",
        help="Output format (default: text).",
    )
    parser.add_argument(
        "--show-secrets",
        action="store_true",
        help="Reveal breached passwords/hashes instead of redacting them.",
    )
    parser.add_argument(
        "--list-modules",
        action="store_true",
        help="List available modules and exit.",
    )
    parser.add_argument("--version", action="version", version=f"mosint {__version__}")
    return parser


def _list_modules() -> int:
    print("Available modules:")
    for cls in ALL_MODULES:
        print(f"  {cls.name:<12} {cls.title}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.list_modules:
        return _list_modules()

    if not args.email:
        parser.error("the following argument is required: email")

    try:
        parse_email(args.email)
    except InvalidEmailError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    module_names = None
    if args.modules:
        module_names = [name.strip() for name in args.modules.split(",") if name.strip()]
    try:
        modules = select_modules(module_names)
    except KeyError as exc:
        print(f"error: unknown module(s): {exc}", file=sys.stderr)
        return 2

    config = load_config(args.config)
    scanner = Scanner(config, modules=modules)

    if args.output == "text":
        print(USE_NOTICE, file=sys.stderr)

    report = scanner.scan(args.email)

    if args.output == "json":
        print(render_json(report, show_secrets=args.show_secrets))
    else:
        print(render_text(report, show_secrets=args.show_secrets))

    any_error = any(result.status.value == "error" for result in report.results)
    return 1 if any_error else 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
