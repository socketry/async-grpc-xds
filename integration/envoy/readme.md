# Envoy Integration Test

This integration test exercises the Ruby xDS control plane's dedicated CDS and EDS services against Envoy.

It publishes a cluster and endpoint, confirms Envoy accepted both, replaces the endpoint, and confirms Envoy applied the update without rejecting either resource.

Run it from the project root:

```bash
bundle exec bake test:integration name=envoy
```
