#!/usr/bin/env python3
"""amux `codex` MCP server: a stdio shim over `codex exec`.

Codex CLI removed `codex mcp-server` in 0.154.0 (deprecated 0.149.1), so the
`codex` MCP tool the amux skills call no longer has a native provider. This
script serves that tool itself: each `tools/call` runs one non-interactive
`codex exec` and returns the agent's final message as text.

It keeps the tool name (`codex`) and the parameter names the removed server
used (`prompt`, `model`, `sandbox`, `cwd`, `profile`, `config`), so the skills
and agents that call `mcp__plugin_amux_codex__codex` are unchanged. It is a
one-shot interface: there is no `codex-reply`, because no amux skill continues
a Codex thread.

Standard library only; speaks newline-delimited JSON-RPC 2.0 on stdin/stdout.
Logs go to stderr (stdout is reserved for the protocol). Tool calls run in
threads so parallel reviewers don't queue behind one another.

Environment:
  AMUX_CODEX_BIN      path to the codex binary (default: `codex` on PATH)
  AMUX_CODEX_TIMEOUT  default per-call timeout in seconds (default: 900)
"""

import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading

SERVER_NAME = "amux-codex"
SERVER_VERSION = "1.0.0"
PROTOCOL_VERSION = "2025-06-18"
DEFAULT_TIMEOUT = 900
SANDBOX_MODES = ("read-only", "workspace-write", "danger-full-access")
NOT_FOUND_TEXT = (
    "Codex CLI Not Found: `codex` is not on PATH (set AMUX_CODEX_BIN to point at it). "
    "Install with: npm i -g @openai/codex"
)

TOOL = {
    "name": "codex",
    "description": (
        "Run one non-interactive Codex turn (`codex exec`) and return the agent's final "
        "message. Defaults to a read-only sandbox in the server's working directory. "
        "Reference repository files with @ repo-relative paths (e.g. @src/auth.ts) "
        "resolved against `cwd`. Errors (Codex missing, not logged in, timed out, "
        "non-zero exit) come back as an error result whose text starts with 'Codex'."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "prompt": {"type": "string", "description": "The task for Codex."},
            "model": {"type": "string", "description": "Model name passed to `codex exec -m`."},
            "sandbox": {
                "type": "string",
                "enum": list(SANDBOX_MODES),
                "default": "read-only",
                "description": "Sandbox policy for commands Codex runs.",
            },
            "cwd": {
                "type": "string",
                "description": "Working root for the agent (`codex exec -C`). Defaults to this server's cwd.",
            },
            "profile": {"type": "string", "description": "Codex config profile (`codex exec -p`)."},
            "config": {
                "type": "object",
                "description": "Config overrides as key/value pairs, each passed as `-c key=value`.",
                "additionalProperties": True,
            },
            "output-schema": {
                "type": "object",
                "description": "JSON Schema the final message must satisfy (`--output-schema`).",
                "additionalProperties": True,
            },
            "timeout-seconds": {
                "type": "number",
                "description": "Kill the run after this many seconds (default: AMUX_CODEX_TIMEOUT or 900).",
            },
        },
        "required": ["prompt"],
        "additionalProperties": True,
    },
}

_write_lock = threading.Lock()
_procs_lock = threading.Lock()
_procs = {}  # request id -> running codex subprocess
_cancelled = set()  # request ids the client cancelled


def log(msg):
    sys.stderr.write(f"[{SERVER_NAME}] {msg}\n")
    sys.stderr.flush()


def send(message):
    data = json.dumps(message, separators=(",", ":")).encode("utf-8") + b"\n"
    with _write_lock:
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()


def reply(req_id, result):
    send({"jsonrpc": "2.0", "id": req_id, "result": result})


def reply_error(req_id, code, message):
    send({"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}})


def text_result(text, is_error=False):
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def toml_value(value):
    """Render a JSON value for `-c key=value`; Codex parses the value as TOML."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value)
    return json.dumps(value)  # lists/objects: JSON is valid TOML for these shapes


def build_command(args, codex_bin, last_message_path, schema_path):
    cmd = [codex_bin, "exec", "--skip-git-repo-check", "--color", "never",
           "--output-last-message", last_message_path]
    cwd = args.get("cwd")
    if cwd:
        cmd += ["-C", cwd]
    model = args.get("model")
    if model:
        cmd += ["-m", model]
    sandbox = args.get("sandbox") or "read-only"
    if sandbox not in SANDBOX_MODES:
        raise ValueError(f"sandbox must be one of {', '.join(SANDBOX_MODES)}; got {sandbox!r}")
    cmd += ["-s", sandbox]
    profile = args.get("profile")
    if profile:
        cmd += ["-p", profile]
    config = args.get("config") or {}
    if not isinstance(config, dict):
        raise ValueError("config must be an object of key/value overrides")
    for key, value in config.items():
        cmd += ["-c", f"{key}={toml_value(value)}"]
    if schema_path:
        cmd += ["--output-schema", schema_path]
    cmd.append("-")  # prompt on stdin
    return cmd


def _signal_group(proc, sig):
    try:
        os.killpg(proc.pid, sig)  # the run was started with start_new_session, so pgid == pid
    except ProcessLookupError:
        pass
    except OSError:
        try:
            proc.send_signal(sig)
        except ProcessLookupError:
            pass


def kill_tree(proc):
    """Stop a codex run and everything it spawned.

    The npm `codex` wrapper spawns the native binary as a child and only forwards
    catchable signals; killing the wrapper alone leaves that child alive and
    holding our pipes, so communicate() would never return. The run is started in
    its own process group: TERM the group, give it a moment, then KILL the group,
    which also sweeps any member that outlived the wrapper.
    """
    if proc.poll() is not None:
        return
    _signal_group(proc, signal.SIGTERM)
    try:
        proc.wait(timeout=2.0)
    except subprocess.TimeoutExpired:
        pass
    _signal_group(proc, signal.SIGKILL)


def tail(text, limit=4000):
    text = text.strip()
    return text if len(text) <= limit else "…" + text[-limit:]


def run_codex(req_id, args):
    prompt = args.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        return text_result("Codex call rejected: `prompt` must be a non-empty string", True)

    codex_bin = os.environ.get("AMUX_CODEX_BIN") or "codex"
    if shutil.which(codex_bin) is None:
        return text_result(NOT_FOUND_TEXT, True)

    cwd = args.get("cwd")
    if cwd and not os.path.isdir(cwd):
        return text_result(f"Codex call rejected: cwd {cwd!r} is not a directory", True)

    try:
        timeout = float(args.get("timeout-seconds") or os.environ.get("AMUX_CODEX_TIMEOUT") or DEFAULT_TIMEOUT)
    except (TypeError, ValueError):
        return text_result("Codex call rejected: timeout-seconds must be a number", True)

    workdir = tempfile.mkdtemp(prefix="amux-codex-")
    last_message_path = os.path.join(workdir, "last-message.txt")
    schema_path = None
    try:
        schema = args.get("output-schema")
        if schema is not None:
            if not isinstance(schema, dict):
                return text_result("Codex call rejected: output-schema must be a JSON Schema object", True)
            schema_path = os.path.join(workdir, "output-schema.json")
            with open(schema_path, "w", encoding="utf-8") as fh:
                json.dump(schema, fh)

        try:
            cmd = build_command(args, codex_bin, last_message_path, schema_path)
        except ValueError as exc:
            return text_result(f"Codex call rejected: {exc}", True)

        log(f"request {req_id}: {' '.join(cmd[:2])} … (cwd={cwd or os.getcwd()}, timeout={timeout:g}s)")
        try:
            proc = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=cwd or None,
                start_new_session=True,  # own process group, so kill_tree can reach the whole tree
            )
        except FileNotFoundError:
            return text_result(NOT_FOUND_TEXT, True)
        except OSError as exc:
            return text_result(f"Codex exec could not start: {exc}", True)

        with _procs_lock:
            _procs[req_id] = proc
        try:
            try:
                stdout, stderr = proc.communicate(prompt.encode("utf-8"), timeout=timeout)
            except subprocess.TimeoutExpired:
                kill_tree(proc)
                stdout, stderr = proc.communicate()
                return text_result(
                    f"Codex timed out after {timeout:g}s and was killed.\n\nstderr tail:\n"
                    f"{tail(stderr.decode('utf-8', 'replace'))}",
                    True,
                )
        finally:
            with _procs_lock:
                _procs.pop(req_id, None)
                was_cancelled = req_id in _cancelled
                _cancelled.discard(req_id)

        last_message = ""
        if os.path.exists(last_message_path):
            with open(last_message_path, encoding="utf-8", errors="replace") as fh:
                last_message = fh.read().strip()

        if was_cancelled:
            return text_result("Codex call cancelled by the client", True)
        if proc.returncode != 0:
            return text_result(
                f"Codex exec failed (exit {proc.returncode}).\n\nstderr tail:\n"
                f"{tail(stderr.decode('utf-8', 'replace'))}",
                True,
            )
        if not last_message:
            return text_result(
                "Codex exec exited 0 but produced no final message.\n\nstdout tail:\n"
                f"{tail(stdout.decode('utf-8', 'replace'))}",
                True,
            )
        return text_result(last_message)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def handle_tools_call(req_id, params):
    name = params.get("name")
    if name != TOOL["name"]:
        reply_error(req_id, -32602, f"Unknown tool: {name}")
        return
    args = params.get("arguments") or {}
    if not isinstance(args, dict):
        reply_error(req_id, -32602, "arguments must be an object")
        return
    try:
        result = run_codex(req_id, args)
    except Exception as exc:  # never let a tool call take the server down
        log(f"request {req_id}: unexpected error: {exc!r}")
        result = text_result(f"Codex shim error: {exc!r}", True)
    reply(req_id, result)


def cancel(params):
    req_id = (params or {}).get("requestId")
    with _procs_lock:
        proc = _procs.get(req_id)
        if proc is not None:
            _cancelled.add(req_id)
    if proc is not None:
        log(f"request {req_id}: cancelled by client")
        kill_tree(proc)


def handle(message):
    if not isinstance(message, dict):
        return
    method = message.get("method")
    req_id = message.get("id")
    params = message.get("params") or {}

    if method is None:
        return  # a response to something we sent; we send nothing, so ignore

    if req_id is None:  # notification
        if method == "notifications/cancelled":
            cancel(params)
        return

    if method == "initialize":
        requested = params.get("protocolVersion")
        reply(req_id, {
            "protocolVersion": requested if isinstance(requested, str) else PROTOCOL_VERSION,
            "capabilities": {"tools": {}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            "instructions": (
                "The `codex` tool runs one `codex exec` turn and returns the final message. "
                "An error result means Codex is unavailable for this call."
            ),
        })
    elif method == "ping":
        reply(req_id, {})
    elif method == "tools/list":
        reply(req_id, {"tools": [TOOL]})
    elif method == "tools/call":
        threading.Thread(target=handle_tools_call, args=(req_id, params), daemon=True).start()
    else:
        reply_error(req_id, -32601, f"Method not found: {method}")


def main():
    for raw in sys.stdin.buffer:
        line = raw.strip()
        if not line:
            continue
        try:
            message = json.loads(line.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            send({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": f"Parse error: {exc}"}})
            continue
        if isinstance(message, list):  # batch
            for item in message:
                handle(item)
        else:
            handle(message)

    # Client closed stdin: stop any runs still in flight and exit.
    with _procs_lock:
        procs = list(_procs.values())
    for proc in procs:
        kill_tree(proc)


if __name__ == "__main__":
    main()
