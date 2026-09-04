"""
Weight Balance Dependency Analysis Server.

This module implements a lightweight HTTP server designed to handle dependency
parsing requests across multiple programming languages for the Weight Balance Neovim plugin.
"""

import argparse
import json
import os
import sys
import threading
import time
import traceback
from http.server import BaseHTTPRequestHandler, HTTPServer

from dependency_parsers.python import PythonParser
from dependency_parsers.node import NodeParser
from dependency_parsers.rust import RustParser
from dependency_parsers.lua import LuaParser


DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8080


PARSERS = {
    "python": PythonParser,
    "javascript": NodeParser,
    "javascriptreact": NodeParser,
    "typescript": NodeParser,
    "typescriptreact": NodeParser,
    "rust": RustParser,
    "lua": LuaParser,
}


def parse_arguments():
    """
    Process command line arguments for the server.

    Returns:
        argparse.Namespace: Parsed command line arguments containing host, port, and parent_pid.
    """

    parser = argparse.ArgumentParser(
        description="Weight Balance dependency analysis server"
    )

    parser.add_argument(
        "--host",
        default=DEFAULT_HOST,
        help=(
            f"Host address for the server to listen on "
            f"(default: {DEFAULT_HOST})"
        ),
    )

    parser.add_argument(
        "--port",
        type=int,
        default=DEFAULT_PORT,
        help=(
            f"Port number for the server to listen on "
            f"(default: {DEFAULT_PORT})"
        ),
    )

    parser.add_argument(
        "--parent-pid",
        type=int,
        default=None,
        help=(
            "Parent process PID to monitor for automatic termination"
        ),
    )

    return parser.parse_args()


def monitor_parent(parent_pid):
    """
    Background worker that monitors if the parent process (Neovim) remains active.

    If the parent process terminates, the server exits immediately to prevent orphan processes.

    Args:
        parent_pid (int): Process ID of the parent to monitor.
    """

    while True:
        time.sleep(3)

        try:
            os.kill(parent_pid, 0)

        except OSError:
            os._exit(0)


def send_json_error(handler, status_code, message, error=None):
    """
    Send a structured JSON error response back to the client.

    Args:
        handler (BaseHTTPRequestHandler): The active HTTP request handler instance.
        status_code (int): HTTP status code to return.
        message (str): Descriptive error message.
        error (Exception, optional): Caught exception object for detailed tracebacks.
    """

    response = {
        "success": False,
        "error": message,
    }

    if error:
        response["exception"] = type(error).__name__
        response["details"] = str(error)
        response["traceback"] = traceback.format_exc()

    response_body = json.dumps(
        response
    ).encode("utf-8")

    handler.send_response(status_code)

    handler.send_header(
        "Content-Type",
        "application/json"
    )

    handler.send_header(
        "Content-Length",
        len(response_body)
    )

    handler.end_headers()

    handler.wfile.write(response_body)


class Handler(BaseHTTPRequestHandler):
    """HTTP request handler for managing dependency analysis endpoints."""

    def do_POST(self):
        """Handle incoming HTTP POST requests for health checks and dependency parsing."""

        if self.path == "/":
            response = {
                "status": "ok",
                "service": "weight-balance",
            }

            response_body = json.dumps(
                response
            ).encode("utf-8")

            self.send_response(200)

            self.send_header(
                "Content-Type",
                "application/json"
            )

            self.send_header(
                "Content-Length",
                len(response_body)
            )

            self.end_headers()

            self.wfile.write(response_body)

            return

        if self.path != "/get_dependency_size":
            send_json_error(
                self,
                404,
                "Endpoint not found"
            )
            return

        try:
            content_length = int(
                self.headers.get(
                    "Content-Length",
                    0
                )
            )

            body = self.rfile.read(
                content_length
            )

            data = json.loads(body)

            code = data.get("code")
            language = data.get("language")

            if code is None:
                send_json_error(
                    self,
                    400,
                    "Missing 'code'"
                )
                return

            if language is None:
                send_json_error(
                    self,
                    400,
                    "Missing 'language'"
                )
                return

            language = language.lower()

            print(
                f"Received language: {language}"
            )

            parser_class = PARSERS.get(language)

            if parser_class is None:
                send_json_error(
                    self,
                    400,
                    f"Unsupported language: {language}"
                )
                return

            print(
                f"Selected parser: "
                f"{parser_class.__name__}"
            )

            parser = parser_class(code)

            print(
                f"Executing: "
                f"{parser_class.__name__}.run()"
            )

            result = parser.run()

            response = {
                "success": True,
                "language": language,
                "data": result
            }

            response_body = json.dumps(
                response
            ).encode("utf-8")

            self.send_response(200)

            self.send_header(
                "Content-Type",
                "application/json"
            )

            self.send_header(
                "Content-Length",
                len(response_body)
            )

            self.end_headers()

            self.wfile.write(
                response_body
            )

        except json.JSONDecodeError as error:

            send_json_error(
                self,
                400,
                "Invalid JSON",
                error
            )

        except Exception as error:

            print(
                "\n========== SERVER ERROR =========="
            )

            traceback.print_exc()

            print(
                "==================================\n"
            )

            send_json_error(
                self,
                500,
                "Internal server error",
                error
            )


def main():
    """Initialize server options, start background watchers, and run the HTTP server loop."""

    args = parse_arguments()

    # Validate port range.
    if not 1 <= args.port <= 65535:
        print(
            f"Invalid port: {args.port}",
            file=sys.stderr
        )

        raise SystemExit(1)

    # Start parent process watcher thread if PID is provided.
    if args.parent_pid is not None:

        watcher_thread = threading.Thread(
            target=monitor_parent,
            args=(args.parent_pid,),
            daemon=True
        )

        watcher_thread.start()

    server = HTTPServer(
        (args.host, args.port),
        Handler
    )

    print(
        f"Server listening on "
        f"http://{args.host}:{args.port}"
    )

    try:

        server.serve_forever()

    except KeyboardInterrupt:

        print(
            "\nServer stopped."
        )

    finally:

        server.server_close()


if __name__ == "__main__":
    main()
