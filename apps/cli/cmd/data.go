package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/nsrvel/kuma/apps/cli/internal/view"
	"github.com/spf13/cobra"
)

var (
	flagExportWorkspace string
	flagExportService   string
	flagExportOut       string
	flagImportStrategy  string
)

var dataCmd = &cobra.Command{
	Use:   "data",
	Short: "Backup, export, import, and factory reset Kuma configuration",
}

var dataExportCmd = &cobra.Command{
	Use:   "export",
	Short: "Export workspaces, services, and providers to a JSON backup",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		params := map[string]interface{}{}
		if flagExportService != "" {
			params["scope"] = map[string]string{"type": "service", "id": flagExportService}
		} else if flagExportWorkspace != "" {
			params["scope"] = map[string]string{"type": "workspace", "id": flagExportWorkspace}
		} else {
			params["scope"] = map[string]string{"type": "all"}
		}

		var raw json.RawMessage
		if err := c.Call("data.export", params, &raw); err != nil {
			return err
		}

		if flagExportOut != "" {
			if err := os.WriteFile(flagExportOut, raw, 0644); err != nil {
				return fmt.Errorf("write backup file: %w", err)
			}
			view.Success(fmt.Sprintf("Backup exported successfully to %s", flagExportOut))
			return nil
		}

		fmt.Println(string(raw))
		return nil
	},
}

var dataExportServiceJSONCmd = &cobra.Command{
	Use:   "export-service <service-id>",
	Short: "Export a single service JSON ('Copy Config')",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var raw json.RawMessage
		if err := c.Call("data.export_service_json", map[string]string{"serviceID": id}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		fmt.Println(string(raw))
		return nil
	},
}

var dataImportPreviewCmd = &cobra.Command{
	Use:   "import-preview <backup-file>",
	Short: "Inspect a backup file summary before importing",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		data, err := os.ReadFile(args[0])
		if err != nil {
			return fmt.Errorf("read backup file: %w", err)
		}

		var parsed map[string]interface{}
		if err := json.Unmarshal(data, &parsed); err != nil {
			return fmt.Errorf("invalid json in backup: %w", err)
		}

		var raw json.RawMessage
		if err := c.Call("data.import_preview", map[string]interface{}{"backup": parsed}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var res struct {
			Summary struct {
				WorkspaceCount int      `json:"workspaceCount"`
				ServiceCount   int      `json:"serviceCount"`
				ProviderCount  int      `json:"providerCount"`
				Version        int      `json:"version"`
				Workspaces     []string `json:"workspaceNames"`
			} `json:"summary"`
		}
		if err := json.Unmarshal(raw, &res); err != nil {
			return view.PrintJSON(parsed)
		}

		fmt.Println(view.TitleStyle.Render("Backup Preview Summary"))
		headers := []string{"FIELD", "VALUE"}
		rows := [][]string{
			{"Version", fmt.Sprintf("%d", res.Summary.Version)},
			{"Workspaces", fmt.Sprintf("%d", res.Summary.WorkspaceCount)},
			{"Services", fmt.Sprintf("%d", res.Summary.ServiceCount)},
			{"Providers", fmt.Sprintf("%d", res.Summary.ProviderCount)},
		}
		view.RenderTable(headers, rows)
		return nil
	},
}

var dataImportCmd = &cobra.Command{
	Use:   "import <backup-file>",
	Short: "Import backup file (strategy: merge, replace, rename)",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		data, err := os.ReadFile(args[0])
		if err != nil {
			return fmt.Errorf("read backup file: %w", err)
		}

		var parsed map[string]interface{}
		if err := json.Unmarshal(data, &parsed); err != nil {
			return fmt.Errorf("invalid json in backup: %w", err)
		}

		params := map[string]interface{}{
			"backup":   parsed,
			"strategy": flagImportStrategy,
		}

		var res map[string]interface{}
		if err := c.Call("data.import", params, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success("Backup imported successfully.")
		return nil
	},
}

var dataFactoryResetCmd = &cobra.Command{
	Use:   "factory-reset",
	Short: "Stop all workloads and wipe all database, services, and preferences",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var res map[string]interface{}
		if err := c.Call("data.factory_reset", map[string]interface{}{"confirm": true}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success("Kuma database and preferences factory reset complete.")
		return nil
	},
}

func init() {
	dataExportCmd.Flags().StringVarP(&flagExportWorkspace, "workspace", "w", "", "filter export by workspace ID")
	dataExportCmd.Flags().StringVarP(&flagExportService, "service", "s", "", "filter export by service ID")
	dataExportCmd.Flags().StringVarP(&flagExportOut, "output", "o", "", "output file path (default: stdout)")

	dataImportCmd.Flags().StringVar(&flagImportStrategy, "strategy", "merge", "import strategy (merge, replace, rename)")

	dataCmd.AddCommand(dataExportCmd)
	dataCmd.AddCommand(dataExportServiceJSONCmd)
	dataCmd.AddCommand(dataImportPreviewCmd)
	dataCmd.AddCommand(dataImportCmd)
	dataCmd.AddCommand(dataFactoryResetCmd)

	rootCmd.AddCommand(dataCmd)
}

