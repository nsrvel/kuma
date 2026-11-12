package cmd

import (
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/nsrvel/kuma/apps/cli/internal/view"
	"github.com/spf13/cobra"
)

var (
	flagProviderType string
	flagProviderYAML string
)

var providerCmd = &cobra.Command{
	Use:   "provider",
	Short: "Manage workload execution providers for a service",
}

var providerListCmd = &cobra.Command{
	Use:   "list <service-id>",
	Short: "List providers configured for a service",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var raw json.RawMessage
		if err := c.Call("provider.list", map[string]string{"serviceID": id}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var res struct {
			Providers []struct {
				ID       string `json:"id"`
				Type     string `json:"type"`
				IsActive bool   `json:"isActive"`
			} `json:"providers"`
		}
		if err := json.Unmarshal(raw, &res); err != nil {
			return err
		}

		headers := []string{"ID", "TYPE", "ACTIVE"}
		var rows [][]string
		for _, p := range res.Providers {
			actStr := "-"
			if p.IsActive {
				actStr = "yes"
			}
			rows = append(rows, []string{
				p.ID,
				p.Type,
				actStr,
			})
		}

		view.RenderTable(headers, rows)
		return nil
	},
}

var providerAddCmd = &cobra.Command{
	Use:   "add <service-id>",
	Short: "Add a provider to a service",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		params := map[string]interface{}{
			"serviceID":  id,
			"type":       flagProviderType,
			"yamlConfig": flagProviderYAML,
		}

		var res map[string]interface{}
		if err := c.Call("provider.add", params, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Provider added to service %s", id))
		return nil
	},
}

var providerDeleteCmd = &cobra.Command{
	Use:   "delete <provider-id>",
	Short: "Delete a provider from a service",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var res map[string]interface{}
		if err := c.Call("provider.delete", map[string]string{"id": id}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Provider %s deleted successfully", id))
		return nil
	},
}

var providerSetPortsCmd = &cobra.Command{
	Use:   "set-ports <provider-id> <local-port> <remote-port>",
	Short: "Update port mappings for a provider",
	Args:  cobra.ExactArgs(3),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		lp, _ := strconv.Atoi(args[1])
		rp, _ := strconv.Atoi(args[2])

		params := map[string]interface{}{
			"providerID": id,
			"ports": []map[string]interface{}{
				{"localPort": lp, "remotePort": rp, "protocol": "TCP"},
			},
		}

		var res map[string]interface{}
		if err := c.Call("provider.set_ports", params, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Ports updated for provider %s (%d -> %d)", id, lp, rp))
		return nil
	},
}

func init() {
	providerAddCmd.Flags().StringVarP(&flagProviderType, "type", "t", "docker", "provider type (docker, shell, kubernetes)")
	providerAddCmd.Flags().StringVarP(&flagProviderYAML, "yaml", "y", "", "raw provider YAML configuration")

	providerCmd.AddCommand(providerListCmd)
	providerCmd.AddCommand(providerAddCmd)
	providerCmd.AddCommand(providerDeleteCmd)
	providerCmd.AddCommand(providerSetPortsCmd)

	rootCmd.AddCommand(providerCmd)
}

