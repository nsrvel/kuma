package cmd

import (
	"fmt"
	"time"

	"github.com/nsrvel/kuma/apps/cli/internal/client"
	"github.com/nsrvel/kuma/apps/cli/internal/view"
	"github.com/spf13/cobra"
)

var pingCmd = &cobra.Command{
	Use:   "ping",
	Short: "Check daemon liveness and protocol version",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var res map[string]interface{}
		if err := c.Call("daemon.ping", map[string]string{"clientKind": "cli"}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Daemon is alive (Protocol v%v)", res["protocolVersion"]))
		return nil
	},
}

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show daemon status, paths, memory, and running services",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var status client.DaemonStatus
		if err := c.Call("daemon.status", map[string]interface{}{}, &status); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(status)
		}

		uptime := (time.Duration(status.UptimeSecs) * time.Second).String()
		restAddr := "-"
		if status.RESTListenAddr != nil {
			restAddr = *status.RESTListenAddr
		}

		fmt.Println(view.TitleStyle.Render("Kuma Daemon Status"))
		headers := []string{"KEY", "VALUE"}
		rows := [][]string{
			{"Version", status.Version},
			{"Protocol", status.ProtocolVersion},
			{"Status", view.FormatStatus("running")},
			{"Uptime", uptime},
			{"Services", fmt.Sprintf("%d total, %d running", status.ServiceCount, len(status.RunningServices))},
			{"Workspaces", fmt.Sprintf("%d", status.WorkspaceCount)},
			{"REST API", restAddr},
			{"Socket", status.SocketPath},
			{"Database", status.DBPath},
		}

		view.RenderTable(headers, rows)
		return nil
	},
}

var shutdownCmd = &cobra.Command{
	Use:   "shutdown",
	Short: "Stop the background daemon gracefully",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var res map[string]interface{}
		if err := c.Call("daemon.shutdown", map[string]interface{}{"stopServices": true}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success("Daemon shut down successfully.")
		return nil
	},
}

func init() {
	rootCmd.AddCommand(pingCmd)
	rootCmd.AddCommand(statusCmd)
	rootCmd.AddCommand(shutdownCmd)
}
