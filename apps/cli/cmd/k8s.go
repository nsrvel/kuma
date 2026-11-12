package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/nsrvel/kuma/apps/cli/internal/view"
	"github.com/spf13/cobra"
)

var (
	flagKubeconfigPath  string
	flagKubeconfigPlain string
)

var k8sCmd = &cobra.Command{
	Use:   "k8s",
	Short: "Inspect Kubernetes namespaces and workload resources",
}

var k8sNamespacesCmd = &cobra.Command{
	Use:   "namespaces",
	Short: "List namespaces from active kubeconfig context",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var raw json.RawMessage
		if err := c.Call("k8s.namespaces", map[string]interface{}{}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var res struct {
			Namespaces []string `json:"namespaces"`
		}
		if err := json.Unmarshal(raw, &res); err != nil {
			return err
		}

		headers := []string{"NAMESPACE"}
		var rows [][]string
		for _, ns := range res.Namespaces {
			rows = append(rows, []string{ns})
		}

		view.RenderTable(headers, rows)
		return nil
	},
}

var k8sResourcesCmd = &cobra.Command{
	Use:   "resources <pod|service|deployment> [namespace]",
	Short: "List pods, services, or deployments in a namespace",
	Args:  cobra.RangeArgs(1, 2),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		resType := args[0]
		ns := "default"
		if len(args) > 1 {
			ns = args[1]
		}

		params := map[string]string{
			"resourceType": resType,
			"namespace":    ns,
		}

		var raw json.RawMessage
		if err := c.Call("k8s.resources", params, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var res struct {
			Resources []string `json:"resources"`
		}
		if err := json.Unmarshal(raw, &res); err != nil {
			return err
		}

		headers := []string{fmt.Sprintf("%s (%s)", resType, ns)}
		var rows [][]string
		for _, r := range res.Resources {
			rows = append(rows, []string{r})
		}

		view.RenderTable(headers, rows)
		return nil
	},
}

var kubeconfigCmd = &cobra.Command{
	Use:   "kubeconfig",
	Short: "Manage registered Kubeconfigs and test cluster connectivity",
}

var kubeconfigListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all registered kubeconfigs",
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		var raw json.RawMessage
		if err := c.Call("kubeconfig.list", map[string]interface{}{}, &raw); err != nil {
			return err
		}

		if flagJSON {
			fmt.Println(string(raw))
			return nil
		}

		var res struct {
			Kubeconfigs []struct {
				ID        string `json:"id"`
				Name      string `json:"name"`
				IsDefault bool   `json:"isDefault"`
			} `json:"kubeconfigs"`
		}
		if err := json.Unmarshal(raw, &res); err != nil {
			return err
		}

		headers := []string{"ID", "NAME", "DEFAULT"}
		var rows [][]string
		for _, k := range res.Kubeconfigs {
			defStr := "-"
			if k.IsDefault {
				defStr = "yes"
			}
			rows = append(rows, []string{
				k.ID,
				k.Name,
				defStr,
			})
		}

		view.RenderTable(headers, rows)
		return nil
	},
}

var kubeconfigTestCmd = &cobra.Command{
	Use:   "test <kubeconfig-id>",
	Short: "Probe kubectl version and connectivity for a kubeconfig",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		id := args[0]
		var res map[string]interface{}
		if err := c.Call("kubeconfig.test_connection", map[string]string{"id": id}, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		ok, _ := res["ok"].(bool)
		if ok {
			view.Success(fmt.Sprintf("Cluster connection successful (version: %v)", res["version"]))
		} else {
			view.Error(fmt.Sprintf("Cluster connection failed: %v", res["error"]))
		}

		return nil
	},
}

var kubeconfigCreateCmd = &cobra.Command{
	Use:   "create <name>",
	Short: "Register a new kubeconfig from file or raw YAML",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		c, err := getClient()
		if err != nil {
			return err
		}
		defer c.Close()

		name := args[0]
		yamlContent := flagKubeconfigPlain
		if flagKubeconfigPath != "" {
			bytes, err := os.ReadFile(flagKubeconfigPath)
			if err != nil {
				return fmt.Errorf("read kubeconfig file: %w", err)
			}
			yamlContent = string(bytes)
		}

		if yamlContent == "" {
			return fmt.Errorf("must provide --file or --yaml")
		}

		params := map[string]string{
			"name": name,
			"yaml": yamlContent,
		}

		var res map[string]interface{}
		if err := c.Call("kubeconfig.create", params, &res); err != nil {
			return err
		}

		if flagJSON {
			return view.PrintJSON(res)
		}

		view.Success(fmt.Sprintf("Kubeconfig '%s' registered successfully", name))
		return nil
	},
}

func init() {
	kubeconfigCreateCmd.Flags().StringVarP(&flagKubeconfigPath, "file", "f", "", "path to kubeconfig YAML file")
	kubeconfigCreateCmd.Flags().StringVar(&flagKubeconfigPlain, "yaml", "", "raw kubeconfig YAML string")

	k8sCmd.AddCommand(k8sNamespacesCmd)
	k8sCmd.AddCommand(k8sResourcesCmd)

	kubeconfigCmd.AddCommand(kubeconfigListCmd)
	kubeconfigCmd.AddCommand(kubeconfigTestCmd)
	kubeconfigCmd.AddCommand(kubeconfigCreateCmd)

	rootCmd.AddCommand(k8sCmd)
	rootCmd.AddCommand(kubeconfigCmd)
}

