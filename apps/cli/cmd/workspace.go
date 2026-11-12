package cmd

import (
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/nsrvel/kuma/apps/cli/internal/client"
	"github.com/nsrvel/kuma/apps/cli/internal/view"
	"github.com/spf13/cobra"
)

var workspaceCmd = &cobra.Command{
	Use:   "workspace",
	Short: "Manage service workspaces",
}

var workspaceListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all workspaces",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var raw json.RawMessage
		if err := c.Call("workspace.list", map[string]interface{}{}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var res client.WorkspaceListResponse
		if err := json.Unmarshal(raw, &res); err != nil {
			return err
		}

		headers := []string{"ID", "NAME", "DEFAULT", "ORDER"}
		var rows [][]string
		for idx, w := range res.Workspaces {
			defStr := "-"
			if idx == 0 || w.IsDefault {
				defStr = "yes"
			}
			rows = append(rows, []string{
				w.ID,
				w.Name,
				defStr,
				strconv.Itoa(w.SortOrder),
			})
		}

		view.RenderTable(headers, rows)
		return nil
	},
}

var workspaceCreateCmd = &cobra.Command{
	Use:   "create <name>",
	Short: "Create a new workspace",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		name := args[0]
		var res map[string]interface{}
		if err := c.Call("workspace.create", map[string]string{"name": name}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Workspace '%s' created", name))
		return nil
	},
}

var workspaceDeleteCmd = &cobra.Command{
	Use:   "delete <id>",
	Short: "Delete a workspace by ID",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var res map[string]interface{}
		if err := c.Call("workspace.delete", map[string]string{"id": id}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Workspace %s deleted", id))
		return nil
	},
}

func init() {
	workspaceCmd.AddCommand(workspaceListCmd)
	workspaceCmd.AddCommand(workspaceCreateCmd)
	workspaceCmd.AddCommand(workspaceDeleteCmd)

	rootCmd.AddCommand(workspaceCmd)
}
