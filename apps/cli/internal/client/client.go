package client

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sync/atomic"
	"time"
)

// Request is a standard JSON-RPC 2.0 request
type Request struct {
	JSONRPC string      `json:"jsonrpc"`
	ID      uint64      `json:"id"`
	Method  string      `json:"method"`
	Params  interface{} `json:"params"`
}

// ErrorObject is a JSON-RPC 2.0 error representation
type ErrorObject struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func (e *ErrorObject) Error() string {
	return fmt.Sprintf("rpc error %d: %s", e.Code, e.Message)
}

// Response is a JSON-RPC 2.0 response
type Response struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      *uint64         `json:"id"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *ErrorObject    `json:"error,omitempty"`
}

// Client manages the Unix Domain Socket connection to the Kuma daemon
type Client struct {
	conn       net.Conn
	reader     *bufio.Reader
	seq        uint64
	socketPath string
	timeout    time.Duration
}

// DefaultSocketPath resolves the active Kuma daemon socket path
func DefaultSocketPath() string {
	if s := os.Getenv("KUMA_SOCKET"); s != "" {
		return s
	}
	home, err := os.UserHomeDir()
	if err == nil {
		// Target layout: ~/Library/Application Support/Kuma/run/kuma-daemon.sock
		candidate1 := filepath.Join(home, "Library", "Application Support", "Kuma", "run", "kuma-daemon.sock")
		if _, err := os.Stat(candidate1); err == nil {
			return candidate1
		}
		// Fallback layout: ~/Library/Application Support/Kuma/kuma-daemon.sock
		candidate2 := filepath.Join(home, "Library", "Application Support", "Kuma", "kuma-daemon.sock")
		if _, err := os.Stat(candidate2); err == nil {
			return candidate2
		}
	}
	// Fallback to /tmp default
	return "/tmp/kuma-daemon.sock"
}

// Connect creates a new client connected to the Kuma daemon
func Connect(socketPath string, timeout time.Duration) (*Client, error) {
	if socketPath == "" {
		socketPath = DefaultSocketPath()
	}
	if timeout == 0 {
		timeout = 10 * time.Second
	}

	conn, err := net.DialTimeout("unix", socketPath, timeout)
	if err != nil {
		return nil, fmt.Errorf("could not connect to Kuma daemon at %s: %w\n(is the daemon running? Check with 'kuma status' or start it with './scripts/kuma-daemon.sh start')", socketPath, err)
	}

	c := &Client{
		conn:       conn,
		reader:     bufio.NewReader(conn),
		socketPath: socketPath,
		timeout:    timeout,
	}

	// Handshake: daemon.ping with clientKind: "cli"
	var pong map[string]interface{}
	_ = c.Call("daemon.ping", map[string]string{"clientKind": "cli"}, &pong)

	return c, nil
}

// Close closes the connection
func (c *Client) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}

// Call sends a JSON-RPC request and decodes the result into target
func (c *Client) Call(method string, params interface{}, target interface{}) error {
	id := atomic.AddUint64(&c.seq, 1)
	if params == nil {
		params = map[string]interface{}{}
	}

	req := Request{
		JSONRPC: "2.0",
		ID:      id,
		Method:  method,
		Params:  params,
	}

	data, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("marshal request: %w", err)
	}
	data = append(data, '\n')

	_ = c.conn.SetDeadline(time.Now().Add(c.timeout))
	if _, err := c.conn.Write(data); err != nil {
		return fmt.Errorf("write request: %w", err)
	}

	line, err := c.reader.ReadBytes('\n')
	if err != nil {
		return fmt.Errorf("read response: %w", err)
	}

	var resp Response
	if err := json.Unmarshal(line, &resp); err != nil {
		return fmt.Errorf("unmarshal response: %w", err)
	}

	if resp.Error != nil {
		return resp.Error
	}

	if target != nil {
		if err := json.Unmarshal(resp.Result, target); err != nil {
			return fmt.Errorf("unmarshal result into target: %w", err)
		}
	}

	return nil
}

// RawCall sends a JSON-RPC request and returns the raw JSON message
func (c *Client) RawCall(method string, params interface{}) (json.RawMessage, error) {
	var raw json.RawMessage
	err := c.Call(method, params, &raw)
	if err != nil {
		return nil, err
	}
	if len(raw) == 0 {
		return nil, errors.New("empty response result")
	}
	return raw, nil
}
