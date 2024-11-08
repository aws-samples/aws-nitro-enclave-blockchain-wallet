# secure_server.py

from http.server import HTTPServer, SimpleHTTPRequestHandler
from ssl import PROTOCOL_TLS_SERVER, SSLContext, TLSVersion

DUMMY_RESPONSE = b"""
<html>
<head>
<title>Python Test</title>
</head>

<body>
Test page...success.
</body>
</html>
"""
    
class MyHandler(SimpleHTTPRequestHandler):

    def __init__(self,req,client_addr,server):
        SimpleHTTPRequestHandler.__init__(self,req,client_addr,server)

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", len(DUMMY_RESPONSE))
        self.end_headers()
        self.wfile.write(DUMMY_RESPONSE)

ssl_context = SSLContext(PROTOCOL_TLS_SERVER)
ssl_context.minimum_version = TLSVersion.TLSv1_2
ssl_context.load_cert_chain("/app/certs/cert.pem", "/app/certs/key.pem")
server = HTTPServer(("", 9001), MyHandler)
server.socket = ssl_context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
