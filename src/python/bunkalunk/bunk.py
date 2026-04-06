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
from typing import Any, Dict


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
    verbose: bool = False
    db_path: Path | None = None
    activity_store: Path | None = None
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
    
    def execute_command(self, name: str, args: argparse.Namespace) -> int:
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
        
        # Create context
        ctx = Context(args.verbose)
        
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
    """
    Register explicit local source files and decode them immediately.
    
    Accepts one or more explicit local file paths, verifies file extensions
    are supported, computes content fingerprints, registers source-file rows
    in SQLite, and decodes accepted files into the canonical HDF5 activity store.
    
    Per spec: decode on add is the default workflow.
    
    Initial supported formats:
    - .fit
    """

    @classmethod
    def add_arguments(cls, parser: argparse.ArgumentParser) -> None:
        """Add command-specific arguments for add operation."""
        parser.add_argument("path", nargs="+",
                           help="One or more explicit local file paths to add")
    
    def run(self, ctx: Context, args: argparse.Namespace) -> int:
        """Execute the add command."""
        # TODO: Implement decode on add workflow
        # - Verify each file extension is supported
        # - Read each file and compute SHA-256 fingerprint
        # - Register or update source-file row in SQLite (source_path, content_fingerprint, decode_status, decoded_ref, decode_error)
        # - Decode file into canonical HDF5 schema
        # - Preserve extension fields in auxiliary HDF5 lane
        # - Update decode outcome metadata in SQLite (decode_status=decoded, decoded_ref=<ref>)
        # - Register newly observed extension fields in SQLite field catalog
        # - Emit warning if previously registered path is missing
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
        parser.add_argument("selection", nargs="*",
                           help="Optional selection of files to decode by source_path")
    
    def run(self, ctx: Context, args: argparse.Namespace) -> int:
        """Execute the decode command."""
        # TODO: Implement manual decode pipeline
        # - Accept optional path selection or decode all registered sources
        # - Dispatch to format-specific decoder by filename extension
        # - Extract core fields into canonical HDF5 schema
        # - Capture extension fields in auxiliary HDF5 lane
        # - Update decoded_ref and decode_status in SQLite
        # - Register newly observed extension fields in SQLite catalog
        # - On failure, set decode_status=failed and store decode_error
        return 0


class StatusCommand(Command):
    """
    Report source-file index state.
    
    Displays information about the current state of the source-file index,
    including registration status and decode outcomes.
    """

    def run(self, ctx: Context, args: argparse.Namespace) -> int:
        """Execute the status command."""
        # TODO: Implement status reporting
        # - Query source_files table from SQLite
        # - Display summary of registered files and decode statuses
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

    parser.add_argument("-v", "--verbose", action="store_true",
                       help="Enable verbose output")
    
    parser.add_argument("-d", "--db", type=str,
                       help="Database file (default: $ALA_HELE_DB or .db.sqlite3)")
    
    # Add arguments for each command
    for command_name, command_instance in handler._commands.items():
        command_parser = subparsers.add_parser(command_name,
                                              help=command_instance.help)
        command_instance.add_arguments(command_parser)
    
    return parser


def main(argv: list[str] | None = None) -> None:
    """
    Main entry point for Bunkalunk source manager tool.
    
    Sets up command handler, registers commands, and executes the appropriate command
    based on command-line arguments.
    
    Args:
        argv: Command line arguments (None to use sys.argv)
    """
    # Create command handler
    handler = CommandHandler()
    
    # Register source file management commands
    handler.register_command("add", AddCommand())
    handler.register_command("decode", DecodeCommand())
    handler.register_command("status", StatusCommand())
    
    # Build parser
    parser = build_parser(handler)
    
    # Parse arguments and execute command
    args = parser.parse_args(argv)
    
    if args.command:
        try:
            exit_code = handler.execute_command(args.command, args)
            sys.exit(exit_code)
        except KeyError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
