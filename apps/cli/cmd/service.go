package cmd

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/nsrvel/kuma/apps/cli/internal/client"
	"github.com/nsrvel/kuma/apps/cli/internal/view"
	"github.com/spf13/cobra"
)

var flagWorkspaceID string

var serviceCmd = &cobra.Command{
	Use:   "service",
	Short: "Manage local services (start, stop, status, logs)",
}

var serviceListCmd = &cobra.Command{
	Use:   "list",
	Short: "List services and their runtime status",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		// Resolve workspaceID: use flag or default workspace
		wsID := flagWorkspaceID
		if wsID == "" {
			var wsRes client.WorkspaceListResponse
			if err := c.Call("workspace.list", map[string]interface{}{}, &wsRes); err == nil && len(wsRes.Workspaces) > 0 {
				wsID = wsRes.Workspaces[0].ID
			}
		}

		if wsID == "" {
			return fmt.Errorf("no workspace found. Create one with 'kuma workspace create <name>'")
		}

		var raw json.RawMessage
		if err := c.Call("service.list", map[string]string{"workspaceID": wsID}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var res client.ServiceListResponse
		if err := json.Unmarshal(raw, &res); err != nil {
			return err
		}

		headers := []string{"ID", "NAME", "PROVIDER", "PORTS", "STATUS"}
		var rows [][]string
		for _, s := range res.Items {
			st := s.Runtime.Status
			if s.IsDisabled {
				st = "disabled"
			}

			var portStrs []string
			for _, p := range s.LocalPorts {
				portStrs = append(portStrs, fmt.Sprintf("%d", p))
			}
			ports := strings.Join(portStrs, ", ")
			if ports == "" {
				ports = "-"
			}

			prov := s.ActiveProviderCategory
			if prov == "" {
				prov = "default"
			}

			shortID := s.ID
			if len(shortID) > 8 {
				shortID = shortID[:8]
			}

			rows = append(rows, []string{
				shortID,
				s.Name,
				prov,
				ports,
				view.FormatStatus(st),
			})
		}

		view.RenderTable(headers, rows)
		return nil
	},
}

var serviceStartCmd = &cobra.Command{
	Use:   "start <service-id>",
	Short: "Start a service by ID",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var res map[string]interface{}
		if err := c.Call("service.start", map[string]string{"id": id}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Service %s started", id))
		return nil
	},
}

var serviceStopCmd = &cobra.Command{
	Use:   "stop <service-id>",
	Short: "Stop a running service by ID",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var res map[string]interface{}
		if err := c.Call("service.stop", map[string]string{"id": id}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Service %s stopped", id))
		return nil
	},
}

var serviceRestartCmd = &cobra.Command{
	Use:   "restart <service-id>",
	Short: "Restart a service by ID",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var res map[string]interface{}
		if err := c.Call("service.restart", map[string]string{"id": id}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Service %s restarted", id))
		return nil
	},
}

var serviceStartAllCmd = &cobra.Command{
	Use:   "start-all",
	Short: "Start all enabled services in workspace",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var res map[string]interface{}
		if err := c.Call("service.start_all", map[string]interface{}{}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success("All services started.")
		return nil
	},
}

var serviceStopAllCmd = &cobra.Command{
	Use:   "stop-all",
	Short: "Stop all running services",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var res map[string]interface{}
		if err := c.Call("service.stop_all", map[string]interface{}{}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success("All services stopped.")
		return nil
	},
}

var servicePreflightCmd = &cobra.Command{
	Use:   "preflight <service-id>",
	Short: "Run configuration validation and port check before starting",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var res map[string]interface{}
		if err := c.Call("service.preflight", map[string]string{"id": id}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Preflight check passed for service %s", id))
		return nil
	},
}

func init() {
	serviceListCmd.Flags().StringVarP(&flagWorkspaceID, "workspace", "w", "", "workspace ID filter (default: first active workspace)")

	serviceCmd.AddCommand(serviceListCmd)
	serviceCmd.AddCommand(serviceStartCmd)
	serviceCmd.AddCommand(serviceStopCmd)
	serviceCmd.AddCommand(serviceRestartCmd)
	serviceCmd.AddCommand(serviceStartAllCmd)
	serviceCmd.AddCommand(serviceStopAllCmd)
	serviceCmd.AddCommand(servicePreflightCmd)

	rootCmd.AddCommand(serviceCmd)
}
