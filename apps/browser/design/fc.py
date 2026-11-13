"""Minimal FigCraft MCP client: run(cmd, **params) over figcraft-cli's stdio."""
import json, subprocess

CLI = r"C:\Program Files\FigCraft\figcraft-cli.exe"


class FC:
    def __init__(self, port=47800):
        self.p = subprocess.Popen([CLI, "mcp", "--attach", str(port)], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, text=True, encoding="utf-8")
        self.n = 0
        self._rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                 "clientInfo": {"name": "browser-design", "version": "0"}})
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        self.p.stdin.flush()
        self.vars = {v["name"]: v["id"] for v in self.run("variable.list")["variables"]}

    def _rpc(self, method, params):
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params}) + "\n")
        self.p.stdin.flush()
        while True:
            msg = json.loads(self.p.stdout.readline())
            if msg.get("id") == self.n:
                if "error" in msg:
                    raise RuntimeError(msg["error"])
                return msg["result"]

    def tool(self, name, args):
        r = self._rpc("tools/call", {"name": name, "arguments": args})
        text = "".join(c.get("text", "") for c in r["content"])
        if r.get("isError"):
            raise RuntimeError(text)
        try:
            return json.loads(text)
        except ValueError:
            return text

    def run(self, command, **params):
        return self.tool("run_command", {"command": command, "params": params})

    def bind(self, id, field, var):
        self.run("variable.bind", ids=[id], field=field, variable=self.vars[var])

    def node(self, id):
        r = self._rpc("resources/read", {"uri": f"figcraft://node/{id}"})
        return json.loads(r["contents"][0]["text"])

    def find(self, root, name):
        """Ids of layers named `name` under `root`, depth first."""
        out, stack = [], [self.node(root)]
        while stack:
            n = stack.pop()
            if n.get("name") == name:
                out.append(n["id"])
            stack.extend(reversed(n.get("children", [])))
        return out
