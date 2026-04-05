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
