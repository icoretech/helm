def normalize_server_type(raw_type):
    server_type = (raw_type or "SSE").upper()
    if server_type in ("SSE", "STREAMABLE"):
        return "SSE" if server_type == "SSE" else "STREAMABLE_HTTP"
    return server_type


def _has_value(value):
    return value not in (None, "", [], {})


def server_needs_recreate(current, desired_type):
    current_type = normalize_server_type(current.get("type"))
    if current_type != desired_type:
        return True

    if desired_type in ("SSE", "STREAMABLE_HTTP"):
        return any(
            _has_value(current.get(key))
            for key in ("command", "args", "env")
        )

    if desired_type == "STDIO":
        return any(
            _has_value(current.get(key))
            for key in ("url", "headers", "bearerToken")
        )

    return False


def stale_generated_endpoint_server_names(previous_endpoints, desired_endpoints):
    stale_endpoints = set(previous_endpoints or set()) - set(desired_endpoints or set())
    return {f"{name}-endpoint" for name in stale_endpoints if name}


def orphan_generated_endpoint_server_names(current_servers, current_endpoints, desired_servers):
    current_endpoint_names = set(current_endpoints or set())
    desired_server_names = set(desired_servers or set())
    orphans = set()

    for name in current_servers or set():
        if not isinstance(name, str) or not name.endswith("-endpoint"):
            continue
        if name in desired_server_names:
            continue
        endpoint_name = name[: -len("-endpoint")]
        if endpoint_name not in current_endpoint_names:
            orphans.add(name)

    return orphans
