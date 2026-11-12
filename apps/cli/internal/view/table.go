package view

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/lipgloss/table"
)

var (
	// Palette
	ColorKuma    = lipgloss.Color("#E06C75")
	ColorSuccess = lipgloss.Color("#98C379")
	ColorWarn    = lipgloss.Color("#E5C07B")
	ColorMuted   = lipgloss.Color("#5C6370")
	ColorPrimary = lipgloss.Color("#61AFEF")

	// Styles
	TitleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(ColorKuma).
			MarginBottom(1)

	HeaderStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#DCDFE4"))

	MutedStyle = lipgloss.NewStyle().Foreground(ColorMuted)
)

// PrintJSON pretty prints raw data or structs as JSON
func PrintJSON(data interface{}) error {
	b, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(b))
	return nil
}

// FormatStatus returns an elegant, clean status badge
func FormatStatus(status string) string {
	switch strings.ToLower(status) {
	case "running", "healthy", "ready", "installed":
		return lipgloss.NewStyle().Foreground(ColorSuccess).Render("● running")
	case "starting", "initializing", "restarting":
		return lipgloss.NewStyle().Foreground(ColorWarn).Render("◌ starting")
	case "stopped", "inactive":
		return lipgloss.NewStyle().Foreground(ColorMuted).Render("○ stopped")
	case "error", "failed", "crashed", "missing":
		return lipgloss.NewStyle().Foreground(ColorKuma).Render("✖ error")
	default:
		if status == "" {
			return lipgloss.NewStyle().Foreground(ColorMuted).Render("○ idle")
		}
		return status
	}
}

// RenderTable renders a clean, professional borderless table
func RenderTable(headers []string, rows [][]string) {
	if len(rows) == 0 {
		fmt.Println(MutedStyle.Render("No items found."))
		return
	}

	t := table.New().
		Border(lipgloss.HiddenBorder()).
		Headers(headers...).
		Rows(rows...).
		StyleFunc(func(row, col int) lipgloss.Style {
			if row == table.HeaderRow {
				return HeaderStyle.Padding(0, 2, 0, 0)
			}
			return lipgloss.NewStyle().Padding(0, 2, 0, 0)
		})

	fmt.Println(t.Render())
}

// Success prints a clean success message
func Success(msg string) {
	fmt.Printf("%s %s\n", lipgloss.NewStyle().Foreground(ColorSuccess).Render("✔"), msg)
}

// Error prints a clean error message
func Error(msg string) {
	fmt.Fprintf(os.Stderr, "%s %s\n", lipgloss.NewStyle().Foreground(ColorKuma).Render("✖"), msg)
}

// Info prints a clean info message
func Info(msg string) {
	fmt.Printf("%s %s\n", lipgloss.NewStyle().Foreground(ColorPrimary).Render("→"), msg)
}
