import importlib.util
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "provision_lib.py"
SPEC = importlib.util.spec_from_file_location("provision_lib", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class ProvisionLibTests(unittest.TestCase):
    def test_recreates_when_transport_changes(self):
        current = {
            "type": "STDIO",
            "command": "npx",
            "args": ["-y", "@icoretech/warden-mcp@latest", "--stdio"],
            "env": {"BW_HOST": "https://secret-manager.icorete.ch"},
        }

        self.assertTrue(MODULE.server_needs_recreate(current, "STREAMABLE_HTTP"))

    def test_recreates_when_http_server_keeps_stale_stdio_fields(self):
        current = {
            "type": "STREAMABLE_HTTP",
            "url": "http://example.svc.cluster.local:3005/sse?v=2",
            "command": "npx",
            "args": ["-y", "@icoretech/warden-mcp@latest", "--stdio"],
            "env": {"BW_HOST": "https://secret-manager.icorete.ch"},
        }

        self.assertTrue(MODULE.server_needs_recreate(current, "STREAMABLE_HTTP"))

    def test_keeps_clean_http_server_in_place(self):
        current = {
            "type": "STREAMABLE_HTTP",
            "url": "http://example.svc.cluster.local:3005/sse?v=2",
            "headers": {"X-Test": "1"},
        }

        self.assertFalse(MODULE.server_needs_recreate(current, "STREAMABLE_HTTP"))

    def test_prunes_generated_endpoint_server_for_removed_endpoint(self):
        self.assertEqual(
            MODULE.stale_generated_endpoint_server_names({"bsmart", "icoretech"}, {"icoretech"}),
            {"bsmart-endpoint"},
        )


if __name__ == "__main__":
    unittest.main()
