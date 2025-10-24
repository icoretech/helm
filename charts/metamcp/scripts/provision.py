import os, json, time
import requests
import http.cookiejar as cookiejar
import socket
from urllib.parse import urlparse

def log(msg):
    print(f"[provision] {msg}", flush=True)

NS = os.environ.get('NAMESPACE','default')
SVC = os.environ['SVC']
FRONTEND_PORT = os.environ.get('FRONTEND_PORT','12008')
FRONTEND = f"http://{SVC}:{FRONTEND_PORT}"
BACKEND = f"http://{SVC}:12009"
ADMIN_EMAIL = os.environ.get('ADMIN_EMAIL','admin@example.com')
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD','change-me')

cfg = json.load(open('/cfg/provision.json','r')).get('provision',{})
servers = cfg.get('servers', [])
namespaces = cfg.get('namespaces', [])
endpoints = cfg.get('endpoints', [])

for _ in range(60):
    try:
        if requests.get(f"{BACKEND}/health", timeout=2).status_code == 200:
            break
    except Exception:
        pass
    time.sleep(2)

sess = requests.Session()
sess.headers.update({'Accept':'application/json'})
sess.headers.update({'Host': SVC})
# Persist cookies like curl does (some frameworks are picky about cookie jar semantics)
jar_path = '/tmp/metamcp_cookies.txt'
mozjar = cookiejar.MozillaCookieJar(jar_path)
try:
    if os.path.exists(jar_path):
        mozjar.load(ignore_discard=True, ignore_expires=True)
        # load into requests jar
        for c in mozjar:
            try:
                sess.cookies.set_cookie(c)  # type: ignore[attr-defined]
            except Exception:
                pass
except Exception:
    pass

def signin(retries=8, delay=1.5):
    tried_signup = False
    for i in range(retries):
        if not tried_signup:
            try:
                resp = sess.post(f"{BACKEND}/api/auth/sign-up/email", headers={'Content-Type':'application/json','Host': SVC}, json={'email': ADMIN_EMAIL,'password': ADMIN_PASSWORD,'name':'Admin'}, timeout=6)
                tried_signup = True
            except Exception:
                tried_signup = True
        r = sess.post(f"{BACKEND}/api/auth/sign-in/email", headers={'Content-Type':'application/json','Host': SVC}, json={'email': ADMIN_EMAIL,'password': ADMIN_PASSWORD}, timeout=6)
        if r.status_code == 200:
            try:
                # Accept cookie from response plus token header fallback
                host = SVC.split(':')[0]
                token = r.json().get('token')
                if token:
                    try:
                        sess.cookies.set('better-auth.session_token', token, domain=host, path='/')
                    except Exception:
                        sess.cookies.set('better-auth.session_token', token)
                sess.headers['Authorization'] = f"Bearer {token}"
                # Persist cookies to mozilla jar and reload next time
                try:
                    mozjar.clear()
                    for c in sess.cookies:
                        try:
                            mozjar.set_cookie(c)  # type: ignore[arg-type]
                        except Exception:
                            pass
                    mozjar.save(ignore_discard=True, ignore_expires=True)
                except Exception:
                    pass
                lr = sess.get(f"{BACKEND}/trpc/frontend/frontend.mcpServers.list", headers={'Host': SVC}, params={'input':'{}'}, timeout=6)
                if lr.status_code == 200:
                    return True
            except Exception:
                pass
        time.sleep(delay)
    return False

if not signin():
    log('WARN: signin failed; proceeding and expecting 401s')

def trpc_post(path, body):
    return sess.post(f"{BACKEND}{path}", headers={'Content-Type':'application/json','Host': SVC}, json=body, timeout=12)
def trpc_get(path):
    return sess.get(f"{BACKEND}{path}", headers={'Host': SVC}, timeout=12)

# Map existing servers
srv_map = {}
try:
    lr = trpc_get('/trpc/frontend/frontend.mcpServers.list?input=%7B%7D')
    if lr.ok:
        for s in lr.json().get('result',{}).get('data',{}).get('data',[]):
            srv_map[s['name']] = s['uuid']
except Exception:
    pass

for s in servers:
    if not (s.get('enabled', True)):
        continue
    name = s.get('name'); st = (s.get('type','SSE') or 'SSE').upper()
    if not name or name in srv_map:
        continue
    if st in ('SSE','STREAMABLE'):
        st = 'SSE' if st=='SSE' else 'STREAMABLE_HTTP'
    body = {'name': name, 'type': st}
    if st in ('SSE','STREAMABLE_HTTP'):
        url = s.get('url')
        if not url:
            base = s.get('serviceBase')
            if base:
                suffix = '/mcp' if st=='STREAMABLE_HTTP' else '/sse'
                # ensure scheme
                if base.startswith('http://') or base.startswith('https://'):
                    url = base + suffix
                else:
                    url = 'http://' + base + suffix
            # proactive readiness: if we know serviceBase, wait for port to accept before creating record
            if base:
                try:
                    hostport = base.split('://')[-1]
                    host, port = hostport.split(':')[0], int(hostport.split(':')[1])
                except Exception:
                    host, port = None, None
                if host and port:
                    log(f"[ready] waiting tcp {host}:{port} …")
                    max_tries = 8
                    tried = 0
                    ok = False
                    for _ in range(max_tries):
                        try:
                            with socket.create_connection((host, port), timeout=1.5):
                                ok = True
                                break
                        except Exception:
                            time.sleep(1)
                    log(f"[ready] tcp {host}:{port} -> {'ok' if ok else 'timeout'}")
        if url: body['url'] = url
        if s.get('bearerToken'): body['bearerToken'] = s['bearerToken']
        if s.get('headers'): body['headers'] = s['headers']
    if st == 'STDIO':
        cmd = s.get('command')
        args = s.get('args') or []
        if isinstance(cmd, list) and len(cmd) > 0:
            body['command'] = cmd[0]
            body['args'] = (args + cmd[1:]) if isinstance(args, list) else cmd[1:]
        elif isinstance(cmd, str):
            body['command'] = cmd
            if isinstance(args, list) and args:
                body['args'] = args
        if s.get('env'): body['env'] = s['env']
    r = trpc_post('/trpc/frontend/frontend.mcpServers.create', body)
    if r.ok:
        try:
            srv_map[name] = r.json()['result']['data']['data']['uuid']
            log(f"server created: {name}")
        except Exception:
            log(f"WARN cannot parse uuid for {name}")
    else:
        log(f"WARN server create {name} -> {r.status_code}: {r.text[:160]}")

def ensure_namespace(name):
    ns_uuid = None
    lr = trpc_get('/trpc/frontend/frontend.namespaces.list?input=%7B%7D')
    if lr.ok:
        for ns in lr.json().get('result',{}).get('data',{}).get('data',[]):
            if ns.get('name') == name:
                ns_uuid = ns.get('uuid'); break
    if not ns_uuid:
        r = trpc_post('/trpc/frontend/frontend.namespaces.create', {'name': name})
        if r.ok:
            try:
                ns_uuid = r.json()['result']['data']['data']['uuid']
                log(f"namespace created: {name}")
            except Exception:
                pass
    return ns_uuid

for ns in namespaces:
    name = ns.get('name'); nssrvs = ns.get('servers') or []
    if not name: continue
    nid = ensure_namespace(name)
    if nid and nssrvs:
        trpc_post('/trpc/frontend/frontend.namespaces.update', {'uuid': nid,'name': name,'servers': nssrvs})

def create_endpoint(name, nsref, transport='SSE', extra=None):
    lr = trpc_get('/trpc/frontend/frontend.namespaces.list?input=%7B%7D')
    nid = None
    if lr.ok:
        for ns in lr.json().get('result',{}).get('data',{}).get('data',[]):
            if ns.get('uuid') == nsref or ns.get('name') == nsref:
                nid = ns.get('uuid'); break
    if not nid: return
    # normalize transport
    tr = (transport or 'SSE').upper()
    if tr in ('SSE','STREAMABLE'):
        tr = 'SSE' if tr=='SSE' else 'STREAMABLE_HTTP'
    # find existing endpoint by name
    el = trpc_get('/trpc/frontend/frontend.endpoints.list?input=%7B%7D')
    e_uuid = None
    if el.ok:
        try:
            for e in el.json().get('result',{}).get('data',{}).get('data',[]):
                if e.get('name') == name:
                    e_uuid = e.get('uuid'); break
        except Exception:
            e_uuid = None
    # build extra flags (camelCase as accepted by API)
    flags = {}
    if isinstance(extra, dict):
        for k in ('enableApiKeyAuth','enableOauth','useQueryParamAuth'):
            if k in extra:
                flags[k] = extra[k]
    if e_uuid:
        # update existing endpoint
        up = {'uuid': e_uuid, 'name': name, 'namespaceUuid': nid}
        up.update(flags)
        r = trpc_post('/trpc/frontend/frontend.endpoints.update', up)
        if r.ok:
            log(f"endpoint updated: {name}")
    else:
        # create new endpoint
        body = {'name': name,'namespaceUuid': nid,'transport': tr}
        body.update(flags)
        r = trpc_post('/trpc/frontend/frontend.endpoints.create', body)
        if r.ok: log(f"endpoint created: {name} ({tr})")

for ep in endpoints:
    name = ep.get('name'); nsref = ep.get('namespace') or ep.get('namespaceUuid')
    if not (name and nsref): continue
    extra = {k: ep[k] for k in ('enableApiKeyAuth','enableOauth','useQueryParamAuth') if k in ep}
    create_endpoint(name, nsref, ep.get('transport'), extra)
