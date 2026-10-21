"""Private, authenticated DWG-to-DXF bridge for an x86-64 ODA container."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hmac
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import threading

MAX_INPUT = 15 * 1024 * 1024
MAX_OUTPUT = 32 * 1024 * 1024
JOBS = threading.BoundedSemaphore(2)


def convert(raw):
    with tempfile.TemporaryDirectory(prefix='dwg-') as work:
        source, output = Path(work) / 'input', Path(work) / 'output'
        source.mkdir()
        output.mkdir()
        (source / 'drawing.dwg').write_bytes(raw)
        process = subprocess.Popen(
            ['xvfb-run', '-a', 'ODAFileConverter', str(source), str(output),
             'ACAD2018', 'DXF', '0', '1', '*.dwg'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            process.wait(timeout=25)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise ValueError('Conversion timed out') from None
        files = list(output.glob('*.dxf')) + list(output.glob('*.DXF'))
        if process.returncode or len(files) != 1 or not 0 < files[0].stat().st_size <= MAX_OUTPUT:
            raise ValueError('Conversion failed or output exceeds preview limit')
        return files[0].read_bytes()


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(30)

    def reply(self, status, body, content_type='text/plain; charset=utf-8'):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == '/healthz':
            ready = all(shutil.which(tool) for tool in ('ODAFileConverter', 'xvfb-run'))
            self.reply(200 if ready else 503, b'ready\n' if ready else b'not ready\n')
        else:
            self.reply(404, b'Not found\n')

    def do_POST(self):
        if self.path != '/convert/dwg':
            self.reply(404, b'Not found\n')
            return
        if not hmac.compare_digest(
            self.headers.get('Authorization', '').encode('utf-8'),
            ('Bearer ' + self.server.token).encode('utf-8'),
        ):
            self.reply(401, b'Unauthorized\n')
            return
        try:
            size = int(self.headers.get('Content-Length', '0'))
        except ValueError:
            size = 0
        if not 0 < size <= MAX_INPUT or self.headers.get('Transfer-Encoding'):
            self.reply(413, b'Invalid or excessive body size\n')
            return
        if not JOBS.acquire(blocking=False):
            self.reply(503, b'Converter busy; retry later\n')
            return
        try:
            raw = self.rfile.read(size)
            if len(raw) != size or not raw.startswith(b'AC10'):
                self.reply(400, b'Invalid DWG input\n')
                return
            data = convert(raw)
            self.reply(200, data, 'application/dxf')
        except (ValueError, OSError):
            self.reply(422, b'DWG conversion failed or timed out\n')
        finally:
            JOBS.release()

    def log_message(self, format, *args):
        # Never log uploaded content, tokens or user filenames.
        pass


if __name__ == '__main__':
    token = os.environ.get('CAD_CONVERTER_TOKEN', '')
    if len(token) < 32:
        raise SystemExit('CAD_CONVERTER_TOKEN must contain at least 32 characters')
    server = ThreadingHTTPServer(('0.0.0.0', 8090), Handler)
    server.token = token
    server.serve_forever()
