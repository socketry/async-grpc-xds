# Envoy Integration Test

This integration test exercises the Ruby xDS control plane's dedicated CDS and EDS services against Envoy.

It publishes a cluster and endpoint, confirms Envoy accepted both, replaces the endpoint, and confirms Envoy applied the update without rejecting either resource.

Run it from this directory:

```bash
cd integration/envoy
docker compose up --build --exit-code-from tests
```
