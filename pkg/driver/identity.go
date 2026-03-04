package driver

import (
	"context"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// IdentityServer implements the CSI Identity service.
type IdentityServer struct {
	driver *Driver
	csi.UnimplementedIdentityServer
}

// NewIdentityServer creates a new CSI identity service.
func NewIdentityServer(driver *Driver) *IdentityServer {
	return &IdentityServer{
		driver: driver,
	}
}

// GetPluginInfo returns the driver name and version.
func (s *IdentityServer) GetPluginInfo(ctx context.Context, req *csi.GetPluginInfoRequest) (*csi.GetPluginInfoResponse, error) {
	s.driver.Log().V(LogLevelDebug).Info("GetPluginInfo called")

	if s.driver.name == "" {
		return nil, status.Error(codes.Unavailable, "driver name not configured")
	}

	if s.driver.version == "" {
		return nil, status.Error(codes.Unavailable, "driver version not configured")
	}

	return &csi.GetPluginInfoResponse{
		Name:          s.driver.name,
		VendorVersion: s.driver.version,
	}, nil
}

// GetPluginCapabilities returns the driver's capabilities.
func (s *IdentityServer) GetPluginCapabilities(ctx context.Context, req *csi.GetPluginCapabilitiesRequest) (*csi.GetPluginCapabilitiesResponse, error) {
	s.driver.Log().V(LogLevelDebug).Info("GetPluginCapabilities called")

	return &csi.GetPluginCapabilitiesResponse{
		Capabilities: s.driver.pluginCaps,
	}, nil
}

// Probe checks if the driver is healthy.
// Returns success whenever the driver process is alive (prevents liveness probe kills
// during temporary TrueNAS disconnections). The Ready field indicates whether the
// backend is actually reachable — false means the client is reconnecting.
func (s *IdentityServer) Probe(ctx context.Context, req *csi.ProbeRequest) (*csi.ProbeResponse, error) {
	s.driver.Log().V(LogLevelDebug).Info("Probe called")

	if s.driver.client.Closed() {
		return nil, status.Error(codes.FailedPrecondition, "TrueNAS client closed")
	}

	return &csi.ProbeResponse{
		Ready: &wrapperspb.BoolValue{Value: s.driver.client.Connected()},
	}, nil
}
