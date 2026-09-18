"""Shared process driver. Every worker owns its process group and serial RPC stream."""
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parent
PRIMARY = ['person','location','email','phone','us_ssn','credit_card','ip_address','url','iban']


class Worker:
    def __init__(self, profile, log_path, timeout=300):
        self.profile = profile
        self.timeout = timeout
        self.messages = queue.Queue()
        self.started = time.perf_counter()
        env = os.environ.copy()
        if profile.startswith('redact'):
            node_root = Path(env.get('REDACT_NODE_ROOT', ROOT))
            command, cwd = ['node', str(node_root/'redact_worker.mjs')], node_root
            if profile == 'redact_cpu': env['DAL_COREML_COMPUTE_UNITS'] = 'cpu'
            elif profile == 'redact_default': env.pop('DAL_COREML_COMPUTE_UNITS', None)
            else: raise ValueError(profile)
        else:
            command = ['mix','run','--no-compile','--no-deps-check','--no-start','../worker.exs',profile]
            cwd = ROOT/'consumer'
        Path(log_path).parent.mkdir(parents=True, exist_ok=True)
        self.log = open(log_path,'w')
        self.process = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=self.log, text=True, bufsize=1, start_new_session=True)
        def receive():
            try:
                for line in self.process.stdout:
                    try: self.messages.put(json.loads(line))
                    except json.JSONDecodeError: self.log.write(line); self.log.flush()
            finally: self.messages.put(None)
        self.reader = threading.Thread(target=receive, daemon=True)
        self.reader.start()
        try:
            self.metadata = self.read()
            if self.metadata.get('event') != 'ready': raise RuntimeError('Missing ready handshake')
            self.startup_ms = (time.perf_counter()-self.started)*1000
        except Exception:
            self.close(); raise

    def read(self):
        try: message = self.messages.get(timeout=self.timeout)
        except queue.Empty: raise TimeoutError('worker_response_timeout') from None
        if message is None: raise RuntimeError(f'worker_exited_{self.process.poll()}')
        return message

    def request(self, row):
        request = {'id': row['id'], 'text': row['text']}
        if not row.get('supplemental'): request['entities'] = PRIMARY + ['street_address']
        started = time.perf_counter()
        self.process.stdin.write(json.dumps(request, ensure_ascii=False)+'\n')
        self.process.stdin.flush()
        result = self.read()
        if result.get('id') != row['id']: raise RuntimeError('Response ID mismatch')
        result['roundtrip_ms'] = (time.perf_counter()-started)*1000
        if not self.profile.startswith('redact'):
            result['raw_predictions'] = result.get('predictions', [])
            result['predictions'] = [{**p, 'entity': 'location' if p['entity']=='street_address' else p['entity']}
                                     for p in result.get('predictions', [])]
        size = len(row['text'].encode())
        for p in result.get('predictions', []) + result.get('raw_predictions', []):
            start,end=p['byte_start'],p['byte_end']
            if not 0 <= start < end <= size: raise RuntimeError('Out-of-bounds prediction')
            row['text'].encode()[:start].decode(); row['text'].encode()[:end].decode()
        return result

    def close(self):
        process = getattr(self, 'process', None)
        if process is not None:
            try: process.stdin.close()
            except (BrokenPipeError, OSError): pass
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try: os.killpg(process.pid,signal.SIGTERM)
                except ProcessLookupError: pass
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid,signal.SIGKILL); process.wait()
        if hasattr(self, 'reader'): self.reader.join(timeout=2)
        self.log.close()
