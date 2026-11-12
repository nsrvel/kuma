package cmd

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/nsrvel/kuma/apps/cli/internal/client"
	"github.com/nsrvel/kuma/apps/cli/internal/view"
	"github.com/spf13/cobra"
)

var (
	flagWorkspaceID string
	flagCreateDesc  string
	flagCreatePort  int
	flagCreateType  string
	flagUpdateName  string
	flagUpdateDesc  string
)

var serviceCmd = &cobra.Command{
	Use:   "service",
	Short: "Manage local services (list, get, create, update, delete, start, stop, restart)",
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

var serviceGetCmd = &cobra.Command{
	Use:   "get <service-id>",
	Short: "Get detailed service configuration, providers, and port mappings",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var raw json.RawMessage
		if err := c.Call("service.get", map[string]string{"id": id}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var res struct {
			Service struct {
				ID           string `json:"id"`
				Name         string `json:"name"`
				Description  *string `json:"description"`
				WorkspaceID  string `json:"workspaceID"`
				IsDisabled   bool   `json:"isDisabled"`
				IsStarred    bool   `json:"isStarred"`
				PortMappings []struct {
					LocalPort  int    `json:"localPort"`
					RemotePort int    `json:"remotePort"`
					Protocol   string `json:"protocolType"`
				} `json:"portMappings"`
				Providers []struct {
					ID       string `json:"id"`
					Category string `json:"category"`
					Label    string `json:"label"`
					IsActive bool   `json:"isActive"`
				} `json:"providers"`
			} `json:"service"`
		}

		if err := json.Unmarshal(raw, &res); err != nil {
			return err
		}

		s := res.Service
		fmt.Println(view.TitleStyle.Render("Service Detail: " + s.Name))

		desc := "-"
		if s.Description != nil && *s.Description != "" {
			desc = *s.Description
		}

		var portStrs []string
		for _, p := range s.PortMappings {
			portStrs = append(portStrs, fmt.Sprintf("%d:%d/%s", p.LocalPort, p.RemotePort, p.Protocol))
		}
		ports := strings.Join(portStrs, ", ")
		if ports == "" {
			ports = "-"
		}

		var provStrs []string
		for _, p := range s.Providers {
			marker := ""
			if p.IsActive {
				marker = " (active)"
			}
			provStrs = append(provStrs, p.Category+marker)
		}
		provs := strings.Join(provStrs, ", ")

		headers := []string{"FIELD", "VALUE"}
		rows := [][]string{
			{"ID", s.ID},
			{"Name", s.Name},
			{"Description", desc},
			{"Workspace", s.WorkspaceID},
			{"Disabled", fmt.Sprintf("%v", s.IsDisabled)},
			{"Starred", fmt.Sprintf("%v", s.IsStarred)},
			{"Ports", ports},
			{"Providers", provs},
		}

		view.RenderTable(headers, rows)
		return nil
	},
}

var serviceCreateCmd = &cobra.Command{
	Use:   "create <name>",
	Short: "Create a new service in workspace",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		name := args[0]
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

		params := map[string]interface{}{
			"name":        name,
			"workspaceID": wsID,
			"provider": map[string]interface{}{
				"type": flagCreateType,
			},
		}
		if flagCreateDesc != "" {
			params["description"] = flagCreateDesc
		}
		if flagCreatePort > 0 {
			params["ports"] = []map[string]interface{}{
				{"localPort": flagCreatePort, "remotePort": flagCreatePort},
			}
		}

		var raw json.RawMessage
		if err := c.Call("service.create", params, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		view.Success(fmt.Sprintf("Service '%s' created successfully in workspace %s", name, wsID))
		return nil
	},
}

var serviceUpdateCmd = &cobra.Command{
	Use:   "update <service-id>",
	Short: "Update service configuration (name, description)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		params := map[string]interface{}{
			"id": id,
		}
		if flagUpdateName != "" {
			params["name"] = flagUpdateName
		}
		if flagUpdateDesc != "" {
			params["description"] = flagUpdateDesc
		}

		var raw json.RawMessage
		if err := c.Call("service.update", params, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		view.Success(fmt.Sprintf("Service %s updated successfully", id))
		return nil
	},
}

var serviceDeleteCmd = &cobra.Command{
	Use:   "delete <service-id>",
	Short: "Delete a service by ID",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var res map[string]interface{}
		if err := c.Call("service.delete", map[string]string{"id": id}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Service %s deleted successfully", id))
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

	serviceCreateCmd.Flags().StringVarP(&flagWorkspaceID, "workspace", "w", "", "workspace ID")
	serviceCreateCmd.Flags().StringVarP(&flagCreateDesc, "desc", "d", "", "service description")
	serviceCreateCmd.Flags().IntVarP(&flagCreatePort, "port", "p", 0, "local TCP port mapping")
	serviceCreateCmd.Flags().StringVarP(&flagCreateType, "type", "t", "docker", "provider type (docker, shell, kubernetes)")

	serviceUpdateCmd.Flags().StringVarP(&flagUpdateName, "name", "n", "", "new service name")
	serviceUpdateCmd.Flags().StringVarP(&flagUpdateDesc, "desc", "d", "", "new service description")

	serviceCmd.AddCommand(serviceListCmd)
	serviceCmd.AddCommand(serviceGetCmd)
	serviceCmd.AddCommand(serviceCreateCmd)
	serviceCmd.AddCommand(serviceUpdateCmd)
	serviceCmd.AddCommand(serviceDeleteCmd)
	serviceCmd.AddCommand(serviceStartCmd)
	serviceCmd.AddCommand(serviceStopCmd)
	serviceCmd.AddCommand(serviceRestartCmd)
	serviceCmd.AddCommand(serviceStartAllCmd)
	serviceCmd.AddCommand(serviceStopAllCmd)
	serviceCmd.AddCommand(servicePreflightCmd)

	rootCmd.AddCommand(serviceCmd)
}
