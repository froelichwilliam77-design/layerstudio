from __future__ import annotations

import argparse
import sys

from rich.console import Console

from mosint import __version__
from mosint.config import load_config
from mosint.engine import InvalidEmailError, scan_email
from mosint.report import BANNER, COFFEE, dumps_json, render_report, write_json


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mosint",
        description="All-in-one automated email OSINT framework.",
    )
    parser.add_argument("email", nargs="?", help="Email address to investigate")
    parser.add_argument("-c", "--config", help="Path to YAML config (default: ~/.mosint.yaml)")
    parser.add_argument("-o", "--output", help="Write JSON report to this file")
    parser.add_argument("-s", "--silent", action="store_true", help="Do not print the table report")
    parser.add_argument("--json", action="store_true", help="Print JSON to stdout")
    parser.add_argument("--no-smtp", action="store_true", help="Skip SMTP banner probe on MX hosts")
    parser.add_argument("--coffee", action="store_true", help="Print coffee and exit")
    parser.add_argument("--version", action="version", version=f"mosint {__version__}")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    console = Console(stderr=False)

    if args.coffee:
        console.print(COFFEE)
        return 0

    if not args.email:
        parser.print_help()
        return 1

    if not args.silent and not args.json:
        console.print(f"[bold magenta]{BANNER}[/bold magenta]")
        console.print("[dim]automated email OSINT  ·  mosint {0}[/dim]\n".format(__version__))

    config = load_config(args.config)
    try:
        result = scan_email(args.email, config, probe_smtp=not args.no_smtp)
    except InvalidEmailError as exc:
        console.print(f"[red]{exc}[/red]")
        return 2

    if args.output:
        write_json(result, args.output)
        if not args.silent and not args.json:
            console.print(f"[dim]JSON written to {args.output}[/dim]")

    if args.json:
        sys.stdout.write(dumps_json(result) + "\n")
        return 0

    if not args.silent:
        render_report(result, console)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
