import os, json, time
import requests
import http.cookiejar as cookiejar
import socket
from urllib.parse import urlparse
import base64

from provision_lib import (
    normalize_server_type,
    orphan_generated_endpoint_server_names,
    server_needs_recreate,
    stale_generated_endpoint_server_names,
)

def log(msg):
    print(f"[provision] {msg}", flush=True)

NS = os.environ.get('NAMESPACE','default')
SVC = os.environ['SVC']
FRONTEND_PORT = os.environ.get('FRONTEND_PORT','12008')
FRONTEND = f"http://{SVC}:{FRONTEND_PORT}"
BACKEND = f"http://{SVC}:12009"
ADMIN_EMAIL = os.environ.get('ADMIN_EMAIL','admin@example.com')
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD','change-me')
UPDATE_EXISTING = (os.environ.get('UPDATE_EXISTING','true').lower() == 'true')
PRUNE = (os.environ.get('PRUNE','false').lower() == 'true')
STATE_CONFIGMAP = os.environ.get('STATE_CONFIGMAP', f"{SVC.split('.')[0]}-provision-state")
BOOTSTRAP_CFG_PATH = os.environ.get('BOOTSTRAP_CFG_PATH', '/users/config.json')

STATE_KEYS = ('servers', 'namespaces', 'endpoints')

def k8s_api_request(method: str, path: str, body=None, content_type='application/json'):
    token = open('/var/run/secrets/kubernetes.io/serviceaccount/token','r').read().strip()
    cacert = '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt'
    headers = {'Authorization': f'Bearer {token}'}
    if body is not None:
        headers['Content-Type'] = content_type
    url = f"https://kubernetes.default.svc{path}"
    return requests.request(method, url, headers=headers, json=body, verify=cacert, timeout=5)

def k8s_get_secret_val(name: str, key: str):
    try:
        r = k8s_api_request('GET', f"/api/v1/namespaces/{NS}/secrets/{name}")
        if r.status_code == 200:
            data = r.json().get('data',{})
            b = data.get(key)
            if b:
                return base64.b64decode(b).decode()
    except Exception:
        pass
    return None

def k8s_get_secret_data(name: str):
    try:
        r = k8s_api_request('GET', f"/api/v1/namespaces/{NS}/secrets/{name}")
        if r.status_code == 200:
            data = r.json().get('data',{})
            return {k: base64.b64decode(v).decode() for k,v in data.items()}
    except Exception:
        pass
    return {}

def k8s_get_configmap_data(name: str):
    try:
        r = k8s_api_request('GET', f"/api/v1/namespaces/{NS}/configmaps/{name}")
        if r.status_code == 200:
            return r.json().get('data',{}) or {}
    except Exception:
        pass
    return {}

def merge_refs(refs):
    merged = {}
    for src in (refs or []):
        if not isinstance(src, dict):
            continue
        if 'secretRef' in src and isinstance(src['secretRef'], dict) and src['secretRef'].get('name'):
            merged.update({k: str(v) for k, v in k8s_get_secret_data(src['secretRef']['name']).items()})
        if 'configMapRef' in src and isinstance(src['configMapRef'], dict) and src['configMapRef'].get('name'):
            merged.update({k: str(v) for k, v in k8s_get_configmap_data(src['configMapRef']['name']).items()})
    return merged

def resolve_remote_url(server):
    desired_url = server.get('url')
    if server.get('urlFrom'):
        desired_url = merge_refs(server.get('urlFrom') or []).get('url') or desired_url
    if desired_url:
        return desired_url
    base = server.get('serviceBase')
    if base:
        suffix = '/mcp' if server['type'] == 'STREAMABLE_HTTP' else '/sse'
        if base.startswith('http://') or base.startswith('https://'):
            return base + suffix
        return 'http://' + base + suffix
    raise RuntimeError(
        f"server {server.get('name')}: remote server requires url, urlFrom[url], or a deployable serviceBase"
    )

def load_managed_state():
    data = k8s_get_configmap_data(STATE_CONFIGMAP)
    state = {key: set() for key in STATE_KEYS}
    for key in STATE_KEYS:
        raw = data.get(f"{key}.json")
        if not raw:
            continue
        try:
            items = json.loads(raw)
            if isinstance(items, list):
                state[key] = {item for item in items if isinstance(item, str)}
        except Exception:
            log(f"WARN cannot parse managed state for {key}")
    return state

def save_managed_state(state):
    data = {f"{key}.json": json.dumps(sorted(list(state.get(key, set())))) for key in STATE_KEYS}
    manifest = {
        'apiVersion': 'v1',
        'kind': 'ConfigMap',
        'metadata': {
            'name': STATE_CONFIGMAP,
            'namespace': NS,
            'labels': {
                'app.kubernetes.io/component': 'provision',
                'app.kubernetes.io/managed-by': 'metamcp-provision-job',
            },
        },
        'data': data,
    }
    try:
        existing = k8s_api_request('GET', f"/api/v1/namespaces/{NS}/configmaps/{STATE_CONFIGMAP}")
        if existing.status_code == 404:
            r = k8s_api_request('POST', f"/api/v1/namespaces/{NS}/configmaps", manifest)
        elif existing.status_code == 200:
            patch = {
                'metadata': manifest['metadata'],
                'data': data,
            }
            r = k8s_api_request(
                'PATCH',
                f"/api/v1/namespaces/{NS}/configmaps/{STATE_CONFIGMAP}",
                patch,
                content_type='application/merge-patch+json',
            )
        else:
            raise RuntimeError(f"state configmap read failed -> {existing.status_code}: {existing.text[:160]}")
        if r.status_code not in (200, 201):
            raise RuntimeError(f"state configmap write failed -> {r.status_code}: {r.text[:160]}")
    except Exception as exc:
        raise RuntimeError(f"cannot persist managed state: {exc}") from exc

# Prefer credentials from a mounted file (Secret) to avoid placing passwords in env vars.
try:
    if BOOTSTRAP_CFG_PATH and os.path.exists(BOOTSTRAP_CFG_PATH):
        j = json.load(open(BOOTSTRAP_CFG_PATH, 'r'))
        u0 = (j.get('users') or [{}])[0] or {}
        if isinstance(u0, dict):
            ADMIN_EMAIL = u0.get('email') or ADMIN_EMAIL
            pw = u0.get('password')
            if not pw and isinstance(u0.get('passwordFrom'), dict):
                sk = (u0.get('passwordFrom') or {}).get('secretKeyRef') or {}
                if isinstance(sk, dict) and sk.get('name') and sk.get('key'):
                    pw = k8s_get_secret_val(sk['name'], sk['key'])
            ADMIN_PASSWORD = pw or ADMIN_PASSWORD
except Exception:
    pass

cfg = json.load(open('/cfg/provision.json','r')).get('provision',{})
servers = cfg.get('servers', [])
namespaces = cfg.get('namespaces', [])
endpoints = cfg.get('endpoints', [])
previous_state = load_managed_state()
desired_state = {
    'servers': {s.get('name') for s in servers if s.get('name') and s.get('enabled', True)},
    'namespaces': {ns.get('name') for ns in namespaces if ns.get('name')},
    'endpoints': {ep.get('name') for ep in endpoints if ep.get('name')},
}

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
                # Accept token from JSON (multiple possible shapes) or fall back to session cookie
                host = SVC.split(':')[0]
                token = None
                try:
                    j = r.json()
                    token = (
                        j.get('token')
                        or j.get('sessionToken')
                        or (j.get('data') or {}).get('token')
                        or (j.get('data') or {}).get('sessionToken')
                    )
                except Exception:
                    token = None
                # Try to capture the raw cookie value from Set-Cookie header (preferred for signed cookies)
                raw_cookie = None
                try:
                    sch = r.headers.get('set-cookie') or r.headers.get('Set-Cookie')
                    if sch:
                        # pick either __Secure-better-auth.session_token or better-auth.session_token
                        for nm in ('__Secure-better-auth.session_token','better-auth.session_token'):
                            marker = nm + '='
                            if marker in sch:
                                seg = sch.split(marker,1)[1]
                                raw_cookie = seg.split(';',1)[0]
                                break
                except Exception:
                    raw_cookie = None
                # Prefer raw signed cookie value; otherwise fall back to token from JSON
                cookie_val = raw_cookie or token
                if cookie_val:
                    # set both cookie names to maximize compatibility with secure-cookie deployments
                    for cname in ('better-auth.session_token','__Secure-better-auth.session_token'):
                        try:
                            sess.cookies.set(cname, cookie_val, domain=host, path='/')
                        except Exception:
                            sess.cookies.set(cname, cookie_val)
                    if token:
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
def trpc_post_batch(path, body):
    # Wrap body as {"0": body} and use ?batch=1 to match UI routes
    return sess.post(f"{BACKEND}{path}?batch=1", headers={'Content-Type':'application/json','Host': SVC}, json={"0": body}, timeout=12)

def trpc_result_payload(resp):
    try:
        data = resp.json()
    except Exception:
        return None
    candidates = [
        data.get('result', {}).get('data', {}).get('json'),
        data.get('result', {}).get('data', {}).get('data'),
        data.get('result', {}).get('data'),
        data,
    ]
    for candidate in candidates:
        if isinstance(candidate, dict):
            return candidate
    return None

def ensure_trpc_success(resp, action):
    if not resp.ok:
        raise RuntimeError(f"{action} -> {resp.status_code}: {resp.text[:160]}")
    payload = trpc_result_payload(resp)
    if isinstance(payload, dict) and payload.get('success') is False:
        raise RuntimeError(f"{action} -> {payload.get('message') or 'unknown failure'}")
    return payload

def list_servers():
    lr = trpc_get('/trpc/frontend/frontend.mcpServers.list?input=%7B%7D')
    if not lr.ok:
        return []
    return lr.json().get('result',{}).get('data',{}).get('data',[])

def list_namespaces():
    lr = trpc_get('/trpc/frontend/frontend.namespaces.list?input=%7B%7D')
    if not lr.ok:
        return []
    return lr.json().get('result',{}).get('data',{}).get('data',[])

def list_endpoints():
    lr = trpc_get('/trpc/frontend/frontend.endpoints.list?input=%7B%7D')
    if not lr.ok:
        return []
    return lr.json().get('result',{}).get('data',{}).get('data',[])

def map_by_name(items):
    out = {}
    for item in items:
        name = item.get('name')
        if name:
            out[name] = item
    return out

def normalize_namespace_server_ref(ref):
    if isinstance(ref, str):
        return ref, True
    if isinstance(ref, dict):
        name = ref.get('name')
        if isinstance(name, str) and name:
            return name, bool(ref.get('active', True))
    return None, True

def delete_endpoint(name, endpoints_by_name):
    current = endpoints_by_name.get(name)
    if not current:
        log(f"endpoint already absent: {name}")
        return
    ensure_trpc_success(trpc_post('/trpc/frontend/frontend.endpoints.delete', {'uuid': current['uuid']}), f"endpoint delete {name}")
    log(f"endpoint deleted: {name}")

def delete_namespace(name, namespaces_by_name):
    current = namespaces_by_name.get(name)
    if not current:
        log(f"namespace already absent: {name}")
        return
    ensure_trpc_success(trpc_post('/trpc/frontend/frontend.namespaces.delete', {'uuid': current['uuid']}), f"namespace delete {name}")
    log(f"namespace deleted: {name}")

def delete_server(name, servers_by_name):
    current = servers_by_name.get(name)
    if not current:
        log(f"server already absent: {name}")
        return
    ensure_trpc_success(trpc_post('/trpc/frontend/frontend.mcpServers.delete', {'uuid': current['uuid']}), f"server delete {name}")
    log(f"server deleted: {name}")

# Map existing servers (name -> uuid and full info)
srv_map = {}
srv_info = {}
try:
    for s in list_servers():
        srv_map[s['name']] = s['uuid']
        srv_info[s['name']] = s
except Exception:
    pass

for s in servers:
    if not (s.get('enabled', True)):
        continue
    name = s.get('name'); st = normalize_server_type(s.get('type'))
    if not name:
        continue
    body = {'name': name, 'type': st}
    # Pre-compute desired fields for STDIO so we can also update existing servers
    desired_cmd = None
    desired_args = None
    desired_env = None
    if st == 'STDIO':
        cmd = s.get('command')
        args = s.get('args') or []
        if isinstance(cmd, list) and len(cmd) > 0:
            desired_cmd = cmd[0]
            desired_args = (args + cmd[1:]) if isinstance(args, list) else cmd[1:]
        elif isinstance(cmd, str):
            desired_cmd = cmd
            if isinstance(args, list) and args:
                desired_args = args
        env_map = {}
        if s.get('env') and isinstance(s['env'], dict):
            env_map.update({k:str(v) for k,v in s['env'].items()})
        env_map.update(merge_refs(s.get('envFrom') or []))
        if env_map:
            desired_env = env_map
    desired_url = None
    desired_headers = None
    if st in ('SSE','STREAMABLE_HTTP'):
        desired_url = resolve_remote_url(s)
        header_map = {}
        if s.get('headers') and isinstance(s['headers'], dict):
            header_map.update({k:str(v) for k,v in s['headers'].items()})
        if s.get('headersFrom'):
            header_map.update(merge_refs(s.get('headersFrom') or []))
        if header_map or s.get('headersFrom'):
            desired_headers = header_map
        base = s.get('serviceBase')
        if base:
            try:
                hostport = base.split('://')[-1]
                host, port = hostport.split(':')[0], int(hostport.split(':')[1])
            except Exception:
                host, port = None, None
            if host and port:
                log(f"[ready] waiting tcp {host}:{port} …")
                max_tries = 8
                ok = False
                for _ in range(max_tries):
                    try:
                        with socket.create_connection((host, port), timeout=1.5):
                            ok = True
                            break
                    except Exception:
                        time.sleep(1)
                log(f"[ready] tcp {host}:{port} -> {'ok' if ok else 'timeout'}")
        if desired_url:
            body['url'] = desired_url
        if s.get('bearerToken'):
            body['bearerToken'] = s['bearerToken']
        if desired_headers is not None:
            body['headers'] = desired_headers

    # If server exists and updates are allowed, patch safe fields
    if name in srv_map:
        current = srv_info.get(name, {})
        if UPDATE_EXISTING and server_needs_recreate(current, st):
            log(f"server transport cleanup: recreating {name}")
            delete_server(name, srv_info)
            srv_map.pop(name, None)
            srv_info.pop(name, None)
        if UPDATE_EXISTING and name in srv_map and st in ('SSE','STREAMABLE_HTTP'):
            try:
                patch = {'uuid': current.get('uuid'), 'name': name, 'type': st}
                # Always include required field for HTTP/SSE: url
                if desired_url:
                    patch['url'] = desired_url
                # Optional fields
                if 'bearerToken' in body:
                    patch['bearerToken'] = body['bearerToken']
                if desired_headers is not None:
                    patch['headers'] = desired_headers
                r = trpc_post('/trpc/frontend/frontend.mcpServers.update', patch)
                if r.ok:
                    log(f"server updated: {name}")
                else:
                    log(f"WARN server update {name} -> {r.status_code}: {r.text[:160]}")
            except Exception:
                pass
        elif UPDATE_EXISTING and name in srv_map and st == 'STDIO':
            try:
                patch = {'uuid': current.get('uuid'), 'name': name, 'type': st}
                # Always include required field for STDIO: command
                if desired_cmd is not None:
                    patch['command'] = desired_cmd
                # Include args/env when provided
                if desired_args is not None:
                    patch['args'] = desired_args
                if desired_env is not None:
                    patch['env'] = desired_env
                r = trpc_post('/trpc/frontend/frontend.mcpServers.update', patch)
                if r.ok:
                    log(f"server updated: {name}")
                else:
                    log(f"WARN server update {name} -> {r.status_code}: {r.text[:160]}")
            except Exception:
                pass
        if name in srv_map:
            continue
    if st == 'STDIO':
        if desired_cmd is not None:
            body['command'] = desired_cmd
        if desired_args is not None:
            body['args'] = desired_args
        if desired_env is not None:
            body['env'] = desired_env
    r = trpc_post('/trpc/frontend/frontend.mcpServers.create', body)
    if r.ok:
        try:
            srv_map[name] = r.json()['result']['data']['data']['uuid']
            log(f"server created: {name}")
        except Exception:
            log(f"WARN cannot parse uuid for {name}")
    else:
        log(f"WARN server create {name} -> {r.status_code}: {r.text[:160]}")

def ensure_namespace(name, description=None):
    ns_uuid = None
    existed = False
    lr = trpc_get('/trpc/frontend/frontend.namespaces.list?input=%7B%7D')
    if lr.ok:
        for ns in lr.json().get('result',{}).get('data',{}).get('data',[]):
            if ns.get('name') == name:
                ns_uuid = ns.get('uuid'); existed = True; break
    if not ns_uuid:
        payload = {'name': name}
        if description:
            payload['description'] = description
        r = trpc_post('/trpc/frontend/frontend.namespaces.create', payload)
        if r.ok:
            try:
                ns_uuid = r.json()['result']['data']['data']['uuid']
                log(f"namespace created: {name}")
            except Exception:
                pass
    else:
        # Update description if provided and allowed
        if description and UPDATE_EXISTING:
            try:
                trpc_post('/trpc/frontend/frontend.namespaces.update', {'uuid': ns_uuid,'name': name,'description': description})
            except Exception:
                pass
    return ns_uuid, existed

for ns in namespaces:
    name = ns.get('name'); nssrvs = ns.get('servers') or []
    if not name: continue
    desc = ns.get('description')
    nid, existed = ensure_namespace(name, desc)
    # Map server names to UUIDs if available
    srv_ids = []
    inactive_srv_ids = []
    for ref in nssrvs:
        nm, active = normalize_namespace_server_ref(ref)
        if not nm:
            continue
        sid = srv_map.get(nm)
        if sid:
            srv_ids.append(sid)
            if not active:
                inactive_srv_ids.append((nm, sid))
    # Update namespace membership if allowed or if the namespace was just created
    if nid and srv_ids and (UPDATE_EXISTING or not existed):
        try:
            payload = {'uuid': nid, 'name': name, 'mcpServerUuids': srv_ids}
            if desc:
                payload['description'] = desc
            trpc_post_batch('/trpc/frontend/frontend.namespaces.update', payload)
            for server_name, server_uuid in inactive_srv_ids:
                ensure_trpc_success(
                    trpc_post(
                        '/trpc/frontend/frontend.namespaces.updateServerStatus',
                        {'namespaceUuid': nid, 'serverUuid': server_uuid, 'status': 'INACTIVE'},
                    ),
                    f"namespace server status {name}/{server_name}",
                )
                log(f"namespace server inactive: {name}/{server_name}")
        except Exception as exc:
            log(f"WARN namespace sync {name} -> {exc}")

def create_endpoint(name, nsref, extra=None, description=None, update_existing=True):
    lr = trpc_get('/trpc/frontend/frontend.namespaces.list?input=%7B%7D')
    nid = None
    if lr.ok:
        for ns in lr.json().get('result',{}).get('data',{}).get('data',[]):
            if ns.get('uuid') == nsref or ns.get('name') == nsref:
                nid = ns.get('uuid'); break
    if not nid: return
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
    if description:
        flags['description'] = description
    if e_uuid and update_existing:
        # update existing endpoint (use tRPC batch form as UI does)
        up = {'uuid': e_uuid, 'name': name, 'namespaceUuid': nid}
        up.update(flags)
        r = trpc_post_batch('/trpc/frontend/frontend.endpoints.update', up)
        if r.ok:
            log(f"endpoint updated: {name}")
    else:
        # create new endpoint
        body = {'name': name,'namespaceUuid': nid}
        body.update(flags)
        r = trpc_post('/trpc/frontend/frontend.endpoints.create', body)
        if r.ok: log(f"endpoint created: {name}")

for ep in endpoints:
    name = ep.get('name'); nsref = ep.get('namespace') or ep.get('namespaceUuid')
    if not (name and nsref): continue
    extra = {k: ep[k] for k in ('enableApiKeyAuth','enableOauth','useQueryParamAuth') if k in ep}
    create_endpoint(name, nsref, extra, ep.get('description'), UPDATE_EXISTING)

# Post-fix auto-generated endpoint servers URLs when APP_URL pointed to 12008 at creation time.
# Newer MetaMCP creates a server named '<namespace>-endpoint' per endpoint and derives its URL from APP_URL.
# If APP_URL used the frontend port (12008), the server URL points to the wrong port.
# We normalize such servers to backend port 12009 so connections succeed in-cluster.
try:
    svcs = list_servers()
    # Build namespace->server endpoint name mapping ("<ns>-endpoint")
    ns_names = [ns.get('name') for ns in namespaces if ns.get('name')]
    desired = []
    for ns in ns_names:
        sname = f"{ns}-endpoint"
        for s in svcs:
            if s.get('name') == sname and s.get('type') == 'STREAMABLE_HTTP':
                desired.append((s, ns))
    for s, ns in desired:
        url = s.get('url') or ''
        if ':12008/metamcp/' in url:
            # rewrite to backend port
                fixed = url.replace(':12008/metamcp/', ':12009/metamcp/')
                payload = {'uuid': s['uuid'], 'name': s['name'], 'type': s['type'], 'url': fixed}
                trpc_post('/trpc/frontend/frontend.mcpServers.update', payload)
except Exception:
    pass

if PRUNE:
    stale_endpoints = sorted(previous_state['endpoints'] - desired_state['endpoints'])
    stale_namespaces = sorted(previous_state['namespaces'] - desired_state['namespaces'])
    current_endpoints = map_by_name(list_endpoints())
    current_namespaces = map_by_name(list_namespaces())
    current_servers = map_by_name(list_servers())

    stale_servers = sorted(
        (previous_state['servers'] - desired_state['servers'])
        | stale_generated_endpoint_server_names(previous_state['endpoints'], desired_state['endpoints'])
        | orphan_generated_endpoint_server_names(current_servers.keys(), current_endpoints.keys(), desired_state['servers'])
    )

    for name in stale_endpoints:
        delete_endpoint(name, current_endpoints)

    for name in stale_namespaces:
        delete_namespace(name, current_namespaces)

    for name in stale_servers:
        delete_server(name, current_servers)

    managed_state = {key: set(desired_state[key]) for key in STATE_KEYS}
else:
    managed_state = {key: set(previous_state[key]) | set(desired_state[key]) for key in STATE_KEYS}

save_managed_state(managed_state)
 
