#!/usr/bin/env python3

"""
Bunk: the Bunkalunk source manager CLI.

This module provides the command-line interface for Bunkalunk source file
management and decoding operations.

Per the system spec, this module handles:
- Accepting explicit user-supplied local activity file paths
- Managing the source-file index in SQLite
- Decoding supported file formats into canonical HDF5 representation
- Computing content fingerprints for source files

This module does NOT handle:
- Syncing files from devices or vendor platforms
- Copying files into a project-owned raw archive
- Defining a canonical raw-file storage layout
- Backup or retention of user raw files
- Semantic deduplication of files representing the same real-world ride
- Vendor-specific proprietary API integrations
- Recursive directory ingestion
- Segment matching or analysis result computation
- Serving or exporting analysis results
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Dict

from bunkalunk.bunk_helpers import (
    compute_fingerprint,
    resolve_activity_store,
    resolve_bunk_home,
    resolve_source_path,
    validate_extension,
)
from bunkalunk.cache import resolve_cache_path, write_cache
from bunkalunk.db import (
    Connection,
    DecodeState,
    SourceFile,
    create_connection,
    get_source_file,
    list_source_files_by_decode_state,
    list_source_files_stale_cache,
    record_cache_creation,
    record_decode_outcome,
    record_source_file_fingerprint,
    upsert_source_file,
)
from bunkalunk.formats.fit import fit_to_cache, read_fit


def configure_logger(verbose: bool) -> logging.Logger:
    """Configure and return a logger based on verbosity."""
    logger = logging.getLogger(__name__)
    level = logging.DEBUG if verbose else logging.INFO
    logger.setLevel(level)
    if not logger.hasHandlers():
        format = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter(format))
        logger.addHandler(handler)
    return logger


@dataclass
class Context:
    """Shared context for command execution."""

    db_path: Path
    activity_store: Path
    verbose: bool = False
    logger: logging.Logger | None = None

    def get_logger(self) -> logging.Logger:
        """Get a configured logger for this context."""
        if self.logger is None:
            self.logger = configure_logger(self.verbose)
        return self.logger


class Command(ABC):
    """
    Abstract base class for commands.

    All concrete command implementations should inherit from this class
    and implement the run method.
    """

    @classmethod
    def add_arguments(cls, parser: argparse.ArgumentParser) -> None:
        """Hook for subcommands to add their custom arguments.
        Override this method to add command-specific arguments."""
        pass

    @property
    def help(self) -> str:
        """Returns the docstring for this command"""
        return (self.__doc__ or "").strip().splitlines()[0]

    @abstractmethod
    def run(self, ctx: Context, args: argparse.Namespace) -> int:
        """
        Execute the command.

        Args:
            ctx: Shared execution context
            args: Parsed command line arguments

        Returns:
            Exit code (0 for success, non-zero for error)
        """
        raise NotImplementedError


class CommandHandler:
    """
    Handles execution of commands.

    This class maintains a registry of available commands and
    manages their execution.
    """

    def __init__(self):
        """Initialize the command handler with an empty command registry."""
        self._commands: Dict[str, Command] = {}

    def register_command(self, name: str, command: Command) -> None:
        """
        Register a command.

        Args:
            name: Name of the command
            command: Command instance to register
        """
        if name in self._commands:
            raise ValueError(f"Command '{name}' is already registered")
        self._commands[name] = command

    def execute_command(self, name: str, args: argparse.Namespace, ctx: Context) -> int:
        """
        Execute a registered command.

        Args:
            name: Name of the command to execute
            args: Parsed command line arguments

        Returns:
            Exit code from command execution

        Raises:
            KeyError: If command is not registered
        """
        if name not in self._commands:
            raise KeyError(f"Command '{name}' not found")

        command = self._commands[name]

        return command.run(ctx, args)

    def list_commands(self) -> list[str]:
        """
        List all registered commands.

        Returns:
            A list of registered command names
        """
        return list(self._commands.keys())


# Source file management commands
class AddCommand(Command):
    """Register explicit local source files and decode them immediately.

    Accepts local file path, verifies file extensions are supported, computes
    content fingerprints, registers source-file rows in SQLite, and decodes
    accepted files into the canonical HDF5 activity store.

    Per spec: decode on add is the default workflow.

    Initial supported formats:
    - .fit

    """

    @classmethod
    def add_arguments(cls, parser: argparse.ArgumentParser) -> None:
        """Add command-specific arguments for add operation."""
        parser.add_argument(
            "path", type=Path, help="Local path (i.e. source file) to add to db"
        )

    def run(self, ctx: Context, args: argparse.Namespace) -> int:
        """Execute the add command."""
        path: Path = args.path
        logger = ctx.get_logger()

        is_valid = validate_extension(path)
        if not is_valid:
            logger.error("File '%s' has unsuppored extension '%s'.", path, path.suffix)
            return 1

        source_path = resolve_source_path(path)
        logger.info("add: working on '%s'", source_path)

        with open(source_path, "rb") as f:
            with create_connection(ctx.db_path) as conn:
                content_fingerprint = compute_fingerprint(f)
                source_file = SourceFile(
                    source_path=source_path, content_fingerprint=content_fingerprint
                )
                upsert_source_file(conn, source_file)

                try:
                    fit_data = read_fit(f, logger=logger)

                    cache_data = fit_to_cache(fit_data)
                    cache_path = resolve_cache_path(
                        content_fingerprint, ctx.activity_store
                    )
                    write_cache(cache_path, cache_data)
                    record_cache_creation(conn, cache_data, content_fingerprint)

                    conn.commit()
                except Exception as e:
                    logger.exception(f"Decode on '{source_path}' failed")
                    record_decode_outcome(
                        conn,
                        source_path,
                        state=DecodeState.ERROR,
                        error=str(e),
                    )
                    conn.commit()
                    return 1

                record_decode_outcome(
                    conn, source_file.source_path, state=DecodeState.SUCCESS
                )
        return 0


class DecodeCommand(Command):
    """
    Manually decode or re-decode previously added files.

    Provides explicit control over the decode pipeline for repair,
    retry, or schema-evolution workflows.
    """

    @classmethod
    def add_arguments(cls, parser: argparse.ArgumentParser) -> None:
        """Add command-specific arguments for decode operation."""
        parser.add_argument(
            "path",
            type=str,
            nargs="?",
            default="",
            help="Optional selection of files to decode by source_path",
        )

    def _get_decode_candidates(self, conn: Connection) -> list[SourceFile]:
        """Returns a list of paths that need to be decoded."""
        pending = list_source_files_by_decode_state(conn, DecodeState.PENDING)
        error = list_source_files_by_decode_state(conn, DecodeState.ERROR)
        stale = list_source_files_stale_cache(conn)
        candidates = []
        for source_file in pending + error + stale:
            if source_file not in candidates:
                candidates.append(source_file)

        return candidates

    def run(self, ctx: Context, args: argparse.Namespace) -> int:
        """Execute the decode command."""
        # Branch on number of args
        logger = ctx.get_logger()

        with create_connection(ctx.db_path) as conn:
            if args.path == "":
                source_file_list: list[SourceFile] = self._get_decode_candidates(conn)
            else:
                sf = get_source_file(conn, args.path)
                source_file_list = [sf] if sf else []

            if source_file_list == []:
                logger.error("Input path does not exist in source_files table")
                return 1

            for source_file in source_file_list:
                source_path = source_file.source_path
                if not os.path.isfile(source_path):
                    logger.warning(
                        "Path '%s' no longer exists on disk. Skipping.",
                        source_file.source_path,
                    )
                    continue

                logger.info("Working on '%s'", source_path)

                try:
                    with open(source_path, "rb") as f:
                        fingerprint = compute_fingerprint(f)
                        fit_data = read_fit(f, logger=logger)

                    if fingerprint != source_file.content_fingerprint:
                        logger.warning(
                            "Source file fingerprint has drifted; updating fingerprint"
                        )
                        record_source_file_fingerprint(conn, source_path, fingerprint)
                        conn.commit()

                    cache_data = fit_to_cache(fit_data)
                    cache_path = resolve_cache_path(
                        fingerprint,
                        ctx.activity_store,
                    )
                    write_cache(cache_path, cache_data)
                    record_cache_creation(
                        conn,
                        cache_data,
                        fingerprint,
                    )
                    conn.commit()
                except Exception as e:
                    logger.exception(f"Decode on '{source_path}' failed")
                    record_decode_outcome(
                        conn,
                        source_path,
                        state=DecodeState.ERROR,
                        error=str(e),
                    )
                    conn.commit()
                    return 1

                record_decode_outcome(
                    conn,
                    source_path,
                    state=DecodeState.SUCCESS,
                )

        return 0


def build_parser(handler: CommandHandler) -> argparse.ArgumentParser:
    """
    Build the command-line argument parser for Bunkalunk source manager.

    Args:
        handler: The command handler containing registered commands

    Returns:
        Configured argument parser with subcommands for each registered command
    """
    parser = argparse.ArgumentParser(
        description="Bunkalunk: source file management and decoding"
    )
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Enable verbose output"
    )

    # Add arguments for each command
    for command_name, command_instance in handler._commands.items():
        command_parser = subparsers.add_parser(command_name, help=command_instance.help)
        command_instance.add_arguments(command_parser)

    return parser


def main(argv: list[str] | None = None) -> int:
    """
    Main entry point for Bunkalunk source manager tool.

    Sets up command handler, registers commands, and executes the appropriate command
    based on command-line arguments.

    Args:
        argv: Command line arguments (None to use sys.argv)
    """
    handler = CommandHandler()

    handler.register_command("add", AddCommand())
    handler.register_command("decode", DecodeCommand())

    parser = build_parser(handler)
    args = parser.parse_args(argv)

    bunk_home = resolve_bunk_home(create=True)
    activity_store = resolve_activity_store(create=True)
    if args.command:
        try:
            ctx = Context(
                verbose=args.verbose,
                db_path=bunk_home / "db.sqlite3",
                activity_store=activity_store,
            )
            exit_code = handler.execute_command(args.command, args, ctx)
            return exit_code
        except KeyError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1
    else:
        parser.print_help()
        return 0


if __name__ == "__main__":
    sys.exit(main())
