package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	"github.com/envoyproxy/go-control-plane/pkg/cache/types"
	"github.com/envoyproxy/go-control-plane/pkg/cache/v3"
	"github.com/envoyproxy/go-control-plane/pkg/resource/v3"
	serverv3 "github.com/envoyproxy/go-control-plane/pkg/server/v3"

	clusterv3 "github.com/envoyproxy/go-control-plane/envoy/config/cluster/v3"
	corev3 "github.com/envoyproxy/go-control-plane/envoy/config/core/v3"
	endpointv3 "github.com/envoyproxy/go-control-plane/envoy/config/endpoint/v3"
	discovery "github.com/envoyproxy/go-control-plane/envoy/service/discovery/v3"
)

var (
	port      = flag.Int("port", 18000, "xDS server port")
	adminPort = flag.Int("admin-port", 18001, "Admin HTTP server port")
	upstream  = flag.String("upstream", "backend-1:50051,backend-2:50052,backend-3:50053", "Comma-separated list of upstream endpoints")
)

// Custom hash function that accepts any node ID for testing
type anyNodeHash struct{}

func (h *anyNodeHash) ID(node *corev3.Node) string {
	return "any"
}

func main() {
	flag.Parse()

	ctx := context.Background()
	version := uint64(1)

	// Create snapshot with cluster and endpoints
	snapshot, err := createSnapshot(*upstream, fmt.Sprintf("%d", version))
	if err != nil {
		log.Fatalf("Failed to create snapshot: %v", err)
	}

	// For testing, accept any node ID by using a custom hash that always returns the same key
	// This allows any client to connect and get the same snapshot
	snapshotCache := cache.NewSnapshotCache(false, &anyNodeHash{}, nil)
	if err := snapshotCache.SetSnapshot(ctx, "any", snapshot); err != nil {
		log.Fatalf("Failed to set snapshot: %v", err)
	}
	log.Printf("Set snapshot for any node ID")

	// Create callbacks for logging
	callbacks := serverv3.CallbackFuncs{
		StreamOpenFunc: func(ctx context.Context, streamID int64, typeURL string) error {
			log.Printf("Stream opened: streamID=%d, typeURL=%s", streamID, typeURL)
			return nil
		},
		StreamRequestFunc: func(streamID int64, request *discovery.DiscoveryRequest) error {
			log.Printf("Stream request: streamID=%d, typeURL=%s, resource_names=%v", streamID, request.TypeUrl, request.ResourceNames)
			return nil
		},
	}

	// Create xDS server with callbacks
	srv := serverv3.NewServer(ctx, snapshotCache, callbacks)

	// Start gRPC server
	baseListener, err := net.Listen("tcp", fmt.Sprintf(":%d", *port))
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}
	lis := newTrackingListener(baseListener)

	// Create gRPC server with insecure credentials (for testing without TLS)
	grpcServer := grpc.NewServer(grpc.Creds(insecure.NewCredentials()))
	discovery.RegisterAggregatedDiscoveryServiceServer(grpcServer, srv)

	admin := &adminServer{
		ctx:           ctx,
		cache:         snapshotCache,
		listener:      lis,
		version:       &version,
		currentConfig: *upstream,
	}
	go admin.serve(*adminPort)

	log.Printf("xDS test server listening on :%d", *port)
	log.Printf("xDS admin server listening on :%d", *adminPort)
	log.Printf("Serving cluster 'myservice' with endpoints: %s", *upstream)

	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}

type adminServer struct {
	ctx           context.Context
	cache         cache.SnapshotCache
	listener      *trackingListener
	version       *uint64
	mutex         sync.Mutex
	currentConfig string
}

type endpointsRequest struct {
	Upstream  string   `json:"upstream"`
	Endpoints []string `json:"endpoints"`
}

func (server *adminServer) serve(port int) {
	mux := http.NewServeMux()
	mux.HandleFunc("/endpoints", server.handleEndpoints)
	mux.HandleFunc("/reset-streams", server.handleResetStreams)
	mux.HandleFunc("/status", server.handleStatus)

	if err := http.ListenAndServe(fmt.Sprintf(":%d", port), mux); err != nil {
		log.Fatalf("Failed to serve admin API: %v", err)
	}
}

func (server *adminServer) handleEndpoints(response http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		http.Error(response, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var body endpointsRequest
	if err := json.NewDecoder(request.Body).Decode(&body); err != nil {
		http.Error(response, err.Error(), http.StatusBadRequest)
		return
	}

	upstreams := body.Upstream
	if upstreams == "" {
		upstreams = strings.Join(body.Endpoints, ",")
	}

	nextVersion := atomic.AddUint64(server.version, 1)
	snapshot, err := createSnapshot(upstreams, fmt.Sprintf("%d", nextVersion))
	if err != nil {
		http.Error(response, err.Error(), http.StatusBadRequest)
		return
	}
	if err := server.cache.SetSnapshot(server.ctx, "any", snapshot); err != nil {
		http.Error(response, err.Error(), http.StatusInternalServerError)
		return
	}

	server.mutex.Lock()
	server.currentConfig = upstreams
	server.mutex.Unlock()

	log.Printf("Updated snapshot version %d with endpoints: %s", nextVersion, upstreams)
	writeJSON(response, map[string]any{
		"version":   nextVersion,
		"endpoints": parseEndpoints(upstreams),
	})
}

func (server *adminServer) handleResetStreams(response http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		http.Error(response, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	closed := server.listener.closeConnections()
	log.Printf("Reset %d active xDS connections", closed)
	writeJSON(response, map[string]any{"closed": closed})
}

func (server *adminServer) handleStatus(response http.ResponseWriter, request *http.Request) {
	server.mutex.Lock()
	currentConfig := server.currentConfig
	server.mutex.Unlock()

	writeJSON(response, map[string]any{
		"version":   atomic.LoadUint64(server.version),
		"endpoints": parseEndpoints(currentConfig),
	})
}

func writeJSON(response http.ResponseWriter, value any) {
	response.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(response).Encode(value); err != nil {
		log.Printf("Failed to write JSON response: %v", err)
	}
}

type trackingListener struct {
	net.Listener
	mutex       sync.Mutex
	connections map[net.Conn]struct{}
}

func newTrackingListener(listener net.Listener) *trackingListener {
	return &trackingListener{
		Listener:    listener,
		connections: make(map[net.Conn]struct{}),
	}
}

func (listener *trackingListener) Accept() (net.Conn, error) {
	connection, err := listener.Listener.Accept()
	if err != nil {
		return nil, err
	}

	tracked := &trackedConn{Conn: connection, listener: listener}
	listener.mutex.Lock()
	listener.connections[tracked] = struct{}{}
	listener.mutex.Unlock()

	return tracked, nil
}

func (listener *trackingListener) closeConnections() int {
	listener.mutex.Lock()
	connections := make([]net.Conn, 0, len(listener.connections))
	for connection := range listener.connections {
		connections = append(connections, connection)
	}
	listener.mutex.Unlock()

	for _, connection := range connections {
		_ = connection.Close()
	}

	return len(connections)
}

func (listener *trackingListener) remove(connection net.Conn) {
	listener.mutex.Lock()
	delete(listener.connections, connection)
	listener.mutex.Unlock()
}

type trackedConn struct {
	net.Conn
	listener *trackingListener
	once     sync.Once
}

func (connection *trackedConn) Close() error {
	err := connection.Conn.Close()
	connection.once.Do(func() {
		connection.listener.remove(connection)
	})
	return err
}

func createSnapshot(upstreams string, version string) (*cache.Snapshot, error) {
	// Parse upstream endpoints
	endpoints := parseEndpoints(upstreams)

	// Create cluster
	cluster := &clusterv3.Cluster{
		Name:                 "myservice",
		ClusterDiscoveryType: &clusterv3.Cluster_Type{Type: clusterv3.Cluster_EDS},
		LbPolicy:             clusterv3.Cluster_ROUND_ROBIN,
		EdsClusterConfig: &clusterv3.Cluster_EdsClusterConfig{
			ServiceName: "myservice",
			EdsConfig: &corev3.ConfigSource{
				ConfigSourceSpecifier: &corev3.ConfigSource_Ads{},
			},
		},
	}

	// Create endpoint assignment
	lbEndpoints := make([]*endpointv3.LbEndpoint, 0, len(endpoints))
	for _, ep := range endpoints {
		lbEndpoints = append(lbEndpoints, &endpointv3.LbEndpoint{
			HostIdentifier: &endpointv3.LbEndpoint_Endpoint{
				Endpoint: &endpointv3.Endpoint{
					Address: &corev3.Address{
						Address: &corev3.Address_SocketAddress{
							SocketAddress: &corev3.SocketAddress{
								Protocol: corev3.SocketAddress_TCP,
								Address:  ep.Host,
								PortSpecifier: &corev3.SocketAddress_PortValue{
									PortValue: ep.Port,
								},
							},
						},
					},
				},
			},
			HealthStatus: corev3.HealthStatus_HEALTHY,
		})
	}

	endpointAssignment := &endpointv3.ClusterLoadAssignment{
		ClusterName: "myservice",
		Endpoints: []*endpointv3.LocalityLbEndpoints{
			{
				LbEndpoints: lbEndpoints,
			},
		},
	}

	// Create snapshot
	// types.Resource is proto.Message, which Cluster and ClusterLoadAssignment implement
	return cache.NewSnapshot(
		version,
		map[resource.Type][]types.Resource{
			resource.ClusterType:  {cluster},
			resource.EndpointType: {endpointAssignment},
		},
	)
}

type endpoint struct {
	Host string `json:"host"`
	Port uint32 `json:"port"`
}

func parseEndpoints(upstreams string) []endpoint {
	var endpoints []endpoint
	parts := splitComma(upstreams)
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}

		host, port := parseHostPort(part)
		endpoints = append(endpoints, endpoint{Host: host, Port: port})
	}
	return endpoints
}

func splitComma(s string) []string {
	return strings.Split(s, ",")
}

func parseHostPort(addr string) (string, uint32) {
	parts := strings.Split(addr, ":")
	if len(parts) == 2 {
		var port uint32
		fmt.Sscanf(parts[1], "%d", &port)
		if port > 0 {
			return parts[0], port
		}
	}
	return addr, 50051
}
