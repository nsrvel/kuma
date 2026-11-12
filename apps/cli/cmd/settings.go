package cmd

import (
	"encoding/json"
	"fmt"
	"sort"

	"github.com/nsrvel/kuma/apps/cli/internal/view"
	"github.com/spf13/cobra"
)

var settingsCmd = &cobra.Command{
	Use:   "settings",
	Short: "View and update Kuma preferences and system settings",
}

var settingsListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all settings keys and their effective values",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var raw json.RawMessage
		if err := c.Call("settings.list", map[string]interface{}{}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var res struct {
			Settings map[string]interface{} `json:"settings"`
		}
		if err := json.Unmarshal(raw, &res); err != nil {
			return err
		}

		var keys []string
		for k := range res.Settings {
			keys = append(keys, k)
		}
		sort.Strings(keys)

		headers := []string{"KEY", "VALUE"}
		var rows [][]string
		for _, k := range keys {
			valStr := fmt.Sprintf("%v", res.Settings[k])
			rows = append(rows, []string{k, valStr})
		}

		view.RenderTable(headers, rows)
		return nil
	},
}

var settingsGetCmd = &cobra.Command{
	Use:   "get <key>",
	Short: "Get a specific setting value",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		key := args[0]
		var res map[string]interface{}
		if err := c.Call("settings.get", map[string]string{"key": key}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		fmt.Printf("%s: %v\n", key, res["value"])
		return nil
	},
}

var settingsSetCmd = &cobra.Command{
	Use:   "set <key> <value>",
	Short: "Set a setting value",
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		key := args[0]
		rawVal := args[1]

		var val interface{} = rawVal
		if rawVal == "true" {
			val = true
		} else if rawVal == "false" {
			val = false
		}

		params := map[string]interface{}{
			"key":   key,
			"value": val,
		}

		var res map[string]interface{}
		if err := c.Call("settings.set", params, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Setting '%s' updated to %v", key, val))
		return nil
	},
}

var settingsResetCmd = &cobra.Command{
	Use:   "reset",
	Short: "Reset all preferences to defaults (database remains untouched)",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var res map[string]interface{}
		if err := c.Call("settings.reset", map[string]interface{}{}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success("All settings reset to default values.")
		return nil
	},
}

func init() {
	settingsCmd.AddCommand(settingsListCmd)
	settingsCmd.AddCommand(settingsGetCmd)
	settingsCmd.AddCommand(settingsSetCmd)
	settingsCmd.AddCommand(settingsResetCmd)

	rootCmd.AddCommand(settingsCmd)
}
