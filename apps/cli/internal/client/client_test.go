package client_test

import (
	"bufio"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/nsrvel/kuma/apps/cli/internal/client"
)

func TestClientConnectAndCall(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "kuma-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	sockPath := filepath.Join(tmpDir, "test.sock")
	listener, err := net.Listen("unix", sockPath)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	// Mock server
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()

		reader := bufio.NewReader(conn)
		for {
			line, err := reader.ReadBytes('\n')
			if err != nil {
				return
			}

			var req client.Request
			if err := json.Unmarshal(line, &req); err != nil {
				return
			}

			var result interface{}
			switch req.Method {
			case "daemon.ping":
				result = map[string]interface{}{"pong": true, "protocolVersion": "0.1"}
			case "workspace.list":
				result = client.WorkspaceListResponse{
					Workspaces: []client.Workspace{
						{ID: "ws-1", Name: "Default Workspace", IsDefault: true},
					},
				}
			default:
				result = map[string]interface{}{"status": "ok"}
			}

			resBytes, _ := json.Marshal(result)
			resp := client.Response{
				JSONRPC: "2.0",
				ID:      &req.ID,
				Result:  resBytes,
			}
			respLine, _ := json.Marshal(resp)
			respLine = append(respLine, '\n')
			_, _ = conn.Write(respLine)
		}
	}()

	c, err := client.Connect(sockPath, 2*time.Second)
	if err != nil {
		t.Fatalf("failed to connect: %v", err)
	}
	defer c.Close()

	var wsRes client.WorkspaceListResponse
	if err := c.Call("workspace.list", nil, &wsRes); err != nil {
		t.Fatalf("call failed: %v", err)
	}

	if len(wsRes.Workspaces) != 1 || wsRes.Workspaces[0].Name != "Default Workspace" {
		t.Fatalf("unexpected result: %+v", wsRes)
	}
}
