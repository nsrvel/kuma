package cmd

import (
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/nsrvel/kuma/apps/cli/internal/client"
	"github.com/nsrvel/kuma/apps/cli/internal/view"
	"github.com/spf13/cobra"
)

var envCmd = &cobra.Command{
	Use:   "env",
	Short: "Inspect host environment, binary dependencies, and PATH",
}

var envDepsCmd = &cobra.Command{
	Use:   "dependencies",
	Short: "Scan for container and kubernetes engines (docker, podman, kubectl)",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var raw json.RawMessage
		if err := c.Call("env.dependencies", map[string]interface{}{}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var report client.DependencyReport
		if err := json.Unmarshal(raw, &report); err != nil {
			return err
		}

		headers := []string{"TOOL", "STATUS", "VERSION", "PATH"}
		var rows [][]string
		for _, d := range report.Dependencies {
			st := "missing"
			if d.Installed {
				st = "installed"
			}
			rows = append(rows, []string{
				d.Name,
				view.FormatStatus(st),
				d.Version,
				d.Path,
			})
		}

		view.RenderTable(headers, rows)
		return nil
	},
}

var envPathCmd = &cobra.Command{
	Use:   "path",
	Short: "Show the resolved PATH and binary discovery directories",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var res map[string]interface{}
		if err := c.Call("env.path", map[string]interface{}{}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		fmt.Println(view.TitleStyle.Render("Resolved Daemon PATH"))
		if dirs, ok := res["directories"].([]interface{}); ok {
			for _, d := range dirs {
				fmt.Printf("  • %v\n", d)
			}
		}
		return nil
	},
}

var portsCmd = &cobra.Command{
	Use:   "ports",
	Short: "Check local port conflicts and listener ownership",
}

var portsCheckCmd = &cobra.Command{
	Use:   "check <port>",
	Short: "Check if a TCP port is in use and identify owner process",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		port, err := strconv.Atoi(args[0])
		if err != nil {
			return fmt.Errorf("invalid port number: %s", args[0])
		}

		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var res map[string]interface{}
		if err := c.Call("ports.check", map[string]interface{}{"localPort": port}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		inUse, _ := res["inUse"].(bool)
		if inUse {
			view.Error(fmt.Sprintf("Port %d is currently OCCUPIED by process %v (pid: %v)", port, res["processName"], res["pid"]))
		} else {
			view.Success(fmt.Sprintf("Port %d is FREE to use", port))
		}

		return nil
	},
}

func init() {
	envCmd.AddCommand(envDepsCmd)
	envCmd.AddCommand(envPathCmd)
	portsCmd.AddCommand(portsCheckCmd)

	rootCmd.AddCommand(envCmd)
	rootCmd.AddCommand(portsCmd)
}
