import os, json, time
import requests

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
        if requests.get(f"{FRONTEND}/health", timeout=2).status_code == 200:
            break
    except Exception:
        pass
    time.sleep(2)

sess = requests.Session()
sess.headers.update({'Content-Type':'application/json','Accept':'application/json'})

def signin(retries=5, delay=1.5):
    for i in range(retries):
        try:
            sess.post(f"{BACKEND}/api/auth/sign-up/email", json={'email': ADMIN_EMAIL,'password': ADMIN_PASSWORD,'name':'Admin'}, timeout=6)
        except Exception:
            pass
        r = sess.post(f"{BACKEND}/api/auth/sign-in/email", json={'email': ADMIN_EMAIL,'password': ADMIN_PASSWORD}, timeout=6)
        if r.status_code == 200:
            try:
                token = r.json().get('token')
                if token:
                    sess.headers['Cookie'] = f"better-auth.session_token={token}"
                    sess.headers['Authorization'] = f"Bearer {token}"
                host = SVC.split(':')[0]
                for c in list(sess.cookies):
                    if c.name == 'better-auth.session_token': c.domain = host
                lr = sess.get(f"{BACKEND}/trpc/frontend/frontend.mcpServers.list?input=%7B%7D", timeout=6)
                if lr.status_code == 200:
                    return True
            except Exception:
                pass
        time.sleep(delay)
    return False

signin()

def trpc_post(path, body):
    return sess.post(f"{BACKEND}{path}", json=body, timeout=12)
def trpc_get(path):
    return sess.get(f"{BACKEND}{path}", timeout=12)

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
                url = base + ('/mcp' if st=='STREAMABLE_HTTP' else '/sse')
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
    tr = (transport or 'SSE').upper()
    if tr in ('SSE','STREAMABLE'):
        tr = 'SSE' if tr=='SSE' else 'STREAMABLE_HTTP'
    body = {'name': name,'namespaceUuid': nid,'transport': tr}
    if isinstance(extra, dict): body.update(extra)
    r = trpc_post('/trpc/frontend/frontend.endpoints.create', body)
    if r.ok: log(f"endpoint created: {name} ({tr})")

for ep in endpoints:
    name = ep.get('name'); nsref = ep.get('namespace') or ep.get('namespaceUuid')
    if not (name and nsref): continue
    extra = {k: ep[k] for k in ('enableApiKeyAuth','enableOauth','useQueryParamAuth') if k in ep}
    create_endpoint(name, nsref, ep.get('transport'), extra)

