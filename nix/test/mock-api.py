# Mock of the TypeSafe API. Approves the answer "good reason"; sleeps on "stall".
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        print(json.dumps(request), file=sys.stderr, flush=True)
        if self.headers.get("Authorization") != "Bearer test-key":
            return self.send_error(401)
        answer = request["state"].get("answer", "")
        if answer == "stall":
            time.sleep(30)
        noul = 0.97 if answer == "good reason" else 0.02
        body = json.dumps({"answers": {"authed": {"type": "noul", "noul": noul}}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
