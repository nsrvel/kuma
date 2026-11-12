package cmd

import (
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/nsrvel/kuma/apps/cli/internal/client"
	"github.com/nsrvel/kuma/apps/cli/internal/view"
	"github.com/spf13/cobra"
)

var groupCmd = &cobra.Command{
	Use:   "group",
	Short: "Manage service groups within a workspace",
}

var groupListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all groups in a workspace",
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
			return fmt.Errorf("no workspace found")
		}

		var raw json.RawMessage
		if err := c.Call("group.list", map[string]string{"workspaceID": wsID}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var res struct {
			Groups []client.Group `json:"groups"`
		}
		if err := json.Unmarshal(raw, &res); err != nil {
			return err
		}

		headers := []string{"ID", "NAME", "ORDER"}
		var rows [][]string
		for _, g := range res.Groups {
			rows = append(rows, []string{
				g.ID,
				g.Name,
				strconv.Itoa(g.Order),
			})
		}

		view.RenderTable(headers, rows)
		return nil
	},
}

var groupCreateCmd = &cobra.Command{
	Use:   "create <name>",
	Short: "Create a new group in a workspace",
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

		params := map[string]string{
			"name":        name,
			"workspaceID": wsID,
		}

		var res map[string]interface{}
		if err := c.Call("group.create", params, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Group '%s' created successfully in workspace %s", name, wsID))
		return nil
	},
}

var groupUpdateCmd = &cobra.Command{
	Use:   "update <group-id> <name>",
	Short: "Rename a group",
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		name := args[1]

		var res map[string]interface{}
		if err := c.Call("group.update", map[string]string{"id": id, "name": name}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Group %s updated to '%s'", id, name))
		return nil
	},
}

var groupDeleteCmd = &cobra.Command{
	Use:   "delete <group-id>",
	Short: "Delete a group (services inside stay intact)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var res map[string]interface{}
		if err := c.Call("group.delete", map[string]string{"id": id}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Group %s deleted successfully", id))
		return nil
	},
}

func init() {
	groupListCmd.Flags().StringVarP(&flagWorkspaceID, "workspace", "w", "", "filter by workspace ID")
	groupCreateCmd.Flags().StringVarP(&flagWorkspaceID, "workspace", "w", "", "target workspace ID")

	groupCmd.AddCommand(groupListCmd)
	groupCmd.AddCommand(groupCreateCmd)
	groupCmd.AddCommand(groupUpdateCmd)
	groupCmd.AddCommand(groupDeleteCmd)

	rootCmd.AddCommand(groupCmd)
}
