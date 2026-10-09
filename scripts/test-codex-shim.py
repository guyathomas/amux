#!/usr/bin/env python3
"""Protocol smoke test for mcp/codex.py, run by scripts/validate.sh.

Drives the shim over stdio like an MCP client would and checks, without any
real Codex CLI: the initialize handshake, the tool listing, the "Codex CLI Not
Found" error when `codex` is missing, and the success / non-zero-exit paths
through a fake `codex` that honours `-o` and reads the prompt from stdin.

Usage: python3 -I scripts/test-codex-shim.py mcp/codex.py
"""

import json
import os
import subprocess
import sys
import tempfile

FAKE_CODEX = r'''#!/usr/bin/env python3
import sys
args = sys.argv[1:]
out = args[args.index("-o") + 1] if "-o" in args else args[args.index("--output-last-message") + 1]
prompt = sys.stdin.read()
if "FAIL" in prompt:
    sys.stderr.write("boom\n")
    sys.exit(3)
with open(out, "w") as fh:
    fh.write(json.dumps({"echo": prompt, "argv": args}))
''' .replace("import sys", "import json, sys", 1)


class Client:
    def __init__(self, shim, env):
        self.proc = subprocess.Popen(
            [sys.executable, "-I", shim],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env,
        )
        self.next_id = 0

    def call(self, method, params=None):
        self.next_id += 1
        msg = {"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params or {}}
        self.proc.stdin.write((json.dumps(msg) + "\n").encode())
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            raise AssertionError(f"shim closed stdout while answering {method}")
        reply = json.loads(line)
        assert reply.get("id") == self.next_id, f"reply id mismatch for {method}: {reply}"
        return reply

    def close(self):
        self.proc.stdin.close()
        return self.proc.wait(timeout=10)


def tool_text(reply):
    result = reply["result"]
    return result["content"][0]["text"], result.get("isError", False)


def main():
    shim = sys.argv[1] if len(sys.argv) > 1 else "mcp/codex.py"
    failures = []

    def check(cond, what):
        (failures.append if not cond else (lambda _: None))(what)
        print(("ok:   " if cond else "FAIL: ") + what)

    # 1. No codex on PATH: handshake works, tool is listed, call reports Codex CLI Not Found.
    env = dict(os.environ, PATH="/nonexistent")
    env.pop("AMUX_CODEX_BIN", None)
    c = Client(shim, env)
    init = c.call("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "smoke", "version": "0"}})
    check(init["result"]["protocolVersion"] == "2025-06-18", "initialize echoes the client's protocol version")
    check("tools" in init["result"]["capabilities"], "initialize advertises tools")
    tools = c.call("tools/list")["result"]["tools"]
    check([t["name"] for t in tools] == ["codex"], "tools/list exposes exactly the codex tool")
    check("prompt" in tools[0]["inputSchema"]["required"], "codex tool requires prompt")
    unknown = c.call("tools/call", {"name": "nope", "arguments": {}})
    check(unknown.get("error", {}).get("code") == -32602, "unknown tool is a JSON-RPC -32602 error")
    text, is_error = tool_text(c.call("tools/call", {"name": "codex", "arguments": {"prompt": "hi"}}))
    check(is_error and text.startswith("Codex CLI Not Found"), "missing codex returns 'Codex CLI Not Found' error result")
    check(c.close() == 0, "shim exits 0 when the client closes stdin")

    # 2. Fake codex: success returns the final message; non-zero exit is an error result.
    with tempfile.TemporaryDirectory(prefix="amux-shim-test-") as tmp:
        fake = os.path.join(tmp, "codex")
        with open(fake, "w") as fh:
            fh.write(FAKE_CODEX)
        os.chmod(fake, 0o755)
        env = dict(os.environ, AMUX_CODEX_BIN=fake)
        c = Client(shim, env)
        c.call("initialize", {"protocolVersion": "2024-11-05", "capabilities": {}})
        args = {"prompt": "hello", "model": "gpt-test", "sandbox": "read-only", "cwd": tmp, "config": {"k": "v"}}
        text, is_error = tool_text(c.call("tools/call", {"name": "codex", "arguments": args}))
        check(not is_error, "fake codex success is not an error result")
        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            payload = {}
        argv = payload.get("argv", [])
        check(payload.get("echo") == "hello", "prompt reaches codex on stdin")
        for flag, value in (("-m", "gpt-test"), ("-s", "read-only"), ("-C", tmp), ("-c", 'k="v"')):
            check(flag in argv and argv[argv.index(flag) + 1] == value, f"codex exec gets {flag} {value}")
        check(argv[:1] == ["exec"] and argv[-1] == "-" and "--skip-git-repo-check" in argv, "codex exec invocation shape")
        text, is_error = tool_text(c.call("tools/call", {"name": "codex", "arguments": {"prompt": "please FAIL"}}))
        check(is_error and "exit 3" in text and "boom" in text, "non-zero exit returns an error result with the stderr tail")
        text, is_error = tool_text(c.call("tools/call", {"name": "codex", "arguments": {"prompt": "x", "sandbox": "yolo"}}))
        check(is_error and "sandbox" in text, "invalid sandbox is rejected before codex runs")
        check(c.close() == 0, "shim exits 0 after fake-codex calls")

    if failures:
        print(f"{len(failures)} shim check(s) failed", file=sys.stderr)
        sys.exit(1)
    print("codex shim smoke test passed")


if __name__ == "__main__":
    main()
