package cmd

import (
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/nsrvel/kuma/apps/cli/internal/client"
	"github.com/nsrvel/kuma/apps/cli/internal/view"
	"github.com/spf13/cobra"
)

var (
	flagWSUpdateName string
)

var workspaceCmd = &cobra.Command{
	Use:   "workspace",
	Short: "Manage service workspaces (list, use, get, create, update, delete)",
}

var workspaceListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all workspaces and mark the currently active one",
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

		activeID := c.GetActiveWorkspaceID()

		headers := []string{"ACTIVE", "ID", "NAME", "ORDER"}
		var rows [][]string
		for _, w := range res.Workspaces {
			activeMark := " "
			if w.ID == activeID {
				activeMark = "★"
			}

			shortID := w.ID
			if len(shortID) > 8 {
				shortID = shortID[:8]
			}

			rows = append(rows, []string{
				activeMark,
				shortID,
				w.Name,
				strconv.Itoa(w.SortOrder),
			})
		}

		view.RenderTable(headers, rows)
		return nil
	},
}

var workspaceUseCmd = &cobra.Command{
	Use:   "use <workspace-id-or-name>",
	Short: "Select / switch the currently active workspace",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id, err := c.ResolveWorkspaceID(args[0])
		if err != nil {
			return err
		}

		if err := c.SetActiveWorkspaceID(id); err != nil {
			return err
		}

		view.Success(fmt.Sprintf("Switched active workspace to: %s", id))
		return nil
	},
}

var workspaceGetCmd = &cobra.Command{
	Use:   "get <workspace-id-or-name>",
	Short: "Get details of a workspace",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id, _ := c.ResolveWorkspaceID(args[0])
		var raw json.RawMessage
		if err := c.Call("workspace.get", map[string]string{"id": id}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var res struct {
			Workspace struct {
				ID        string `json:"id"`
				Name      string `json:"name"`
				SortOrder int    `json:"sortOrder"`
				HasImage  bool   `json:"hasImage"`
			} `json:"workspace"`
		}
		if err := json.Unmarshal(raw, &res); err != nil {
			return err
		}

		w := res.Workspace
		fmt.Println(view.TitleStyle.Render("Workspace: " + w.Name))
		headers := []string{"FIELD", "VALUE"}
		rows := [][]string{
			{"ID", w.ID},
			{"Name", w.Name},
			{"Order", strconv.Itoa(w.SortOrder)},
			{"Has Avatar", fmt.Sprintf("%v", w.HasImage)},
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

var workspaceUpdateCmd = &cobra.Command{
	Use:   "update <workspace-id-or-name>",
	Short: "Update workspace name",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id, _ := c.ResolveWorkspaceID(args[0])
		params := map[string]interface{}{
			"id": id,
		}
		if flagWSUpdateName != "" {
			params["name"] = flagWSUpdateName
		} else {
			return fmt.Errorf("please provide --name to update")
		}

		var raw json.RawMessage
		if err := c.Call("workspace.update", params, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		view.Success(fmt.Sprintf("Workspace %s updated to '%s'", id, flagWSUpdateName))
		return nil
	},
}

var workspaceDeleteCmd = &cobra.Command{
	Use:   "delete <workspace-id-or-name>",
	Short: "Delete a workspace by ID or name",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id, _ := c.ResolveWorkspaceID(args[0])
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
	workspaceUpdateCmd.Flags().StringVarP(&flagWSUpdateName, "name", "n", "", "new workspace name")

	workspaceCmd.AddCommand(workspaceListCmd)
	workspaceCmd.AddCommand(workspaceUseCmd)
	workspaceCmd.AddCommand(workspaceGetCmd)
	workspaceCmd.AddCommand(workspaceCreateCmd)
	workspaceCmd.AddCommand(workspaceUpdateCmd)
	workspaceCmd.AddCommand(workspaceDeleteCmd)

	rootCmd.AddCommand(workspaceCmd)
}
