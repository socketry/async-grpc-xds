# Async::GRPC::XDS

xDS support for `async-grpc` clients.

This gem contains the experimental xDS implementation extracted from `async-grpc`, including Envoy xDS protobuf definitions, ADS discovery, CDS/EDS resource handling, and client-side load balancing.

[![Development Status](https://github.com/socketry/async-grpc-xds/workflows/Test/badge.svg)](https://github.com/socketry/async-grpc-xds/actions?workflow=Test)

## Usage

``` ruby
require "async/grpc/xds"

bootstrap = {
	xds_servers: [
		{
			server_uri: "xds-control-plane:18000",
			channel_creds: [{type: "insecure"}]
		}
	],
	node: {
		id: "client-1",
		cluster: "test"
	}
}

xds_client = Async::GRPC::XDS::Client.new("myservice", bootstrap: bootstrap)
stub = xds_client.stub(MyServiceInterface, "myservice")
response = stub.say_hello(request)
```

## Status

This is an early implementation focused on ADS with CDS and EDS. LDS/RDS, full routing semantics, NACK handling, locality weighting, and delta xDS are not complete yet.

## Testing

The `xds/` directory contains a Docker Compose integration environment with a Go xDS control plane and Ruby gRPC backends.

``` bash
docker-compose -f xds/docker-compose.yaml up --exit-code-from tests
```

## Releases

There are no documented releases.

## See Also

  - [async-grpc](https://github.com/socketry/async-grpc)
  - [protocol-grpc](https://github.com/socketry/protocol-grpc)
  - [async-http](https://github.com/socketry/async-http)
