package cmd

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/nsrvel/kuma/apps/cli/internal/view"
	"github.com/spf13/cobra"
)

var logsCmd = &cobra.Command{
	Use:   "logs <service-id>",
	Short: "View logs for a service",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var raw json.RawMessage
		if err := c.Call("logs.tail", map[string]interface{}{"serviceId": id, "limit": 100}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var res struct {
			Entries []struct {
				Timestamp string `json:"timestamp"`
				Level     string `json:"level"`
				Message   string `json:"message"`
			} `json:"entries"`
		}

		if err := json.Unmarshal(raw, &res); err != nil {
			return err
		}

		if len(res.Entries) == 0 {
			fmt.Println(view.MutedStyle.Render("No log entries recorded."))
			return nil
		}

		for _, e := range res.Entries {
			lvl := strings.ToUpper(e.Level)
			switch lvl {
			case "ERROR":
				lvl = lipgloss.NewStyle().Foreground(view.ColorKuma).Render(lvl)
			case "WARN":
				lvl = lipgloss.NewStyle().Foreground(view.ColorWarn).Render(lvl)
			default:
				lvl = lipgloss.NewStyle().Foreground(view.ColorMuted).Render(lvl)
			}
			fmt.Printf("%s [%s] %s\n", view.MutedStyle.Render(e.Timestamp), lvl, e.Message)
		}

		return nil
	},
}

var callCmd = &cobra.Command{
	Use:   "call <method> [json-params]",
	Short: "Call any Kuma daemon RPC method directly (advanced)",
	Args:  cobra.RangeArgs(1, 2),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		method := args[0]
		var params interface{} = map[string]interface{}{}
		if len(args) > 1 {
			var parsed map[string]interface{}
			if err := json.Unmarshal([]byte(args[1]), &parsed); err != nil {
				return fmt.Errorf("invalid json params: %w", err)
			}
			params = parsed
		}

		res, err := c.RawCall(method, params)
		if err != nil {
			return err
		}

		var pretty interface{}
		_ = json.Unmarshal(res, &pretty)
		return view.PrintJSON(pretty)
	},
}

func init() {
	rootCmd.AddCommand(logsCmd)
	rootCmd.AddCommand(callCmd)
}
