package cmd

import (
	"fmt"
	"os"
	"time"

	"github.com/nsrvel/kuma/apps/cli/internal/client"
	"github.com/spf13/cobra"
)

var (
	flagSocket  string
	flagJSON    bool
	flagTimeout time.Duration
)

var rootCmd = &cobra.Command{
	Use:   "kuma",
	Short: "Kuma CLI — developer controls for local dev services",
	Long: `Kuma is a local development services manager and daemon.
This CLI connects to the running Kuma daemon over Unix Domain Socket.`,
	SilenceUsage:  true,
	SilenceErrors: true,
}

// Execute runs the root command
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().StringVarP(&flagSocket, "socket", "s", "", "daemon socket path (default: auto-discover)")
	rootCmd.PersistentFlags().BoolVar(&flagJSON, "json", false, "output results as JSON")
	rootCmd.PersistentFlags().DurationVar(&flagTimeout, "timeout", 10*time.Second, "request timeout duration")
}

func getClient() (*client.Client, error) {
	return client.Connect(flagSocket, flagTimeout)
}
