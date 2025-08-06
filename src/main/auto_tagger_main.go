package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"../tagging"
)

// Version information
var (
	Version   = "1.7.1"
	BuildDate = "unknown"
	GitCommit = "unknown"
)

func main() {
	// Parse command line flags
	var (
		configPath = flag.String("config", "", "Configuration file path")
		verbose    = flag.Bool("verbose", false, "Verbose output")
		jsonOutput = flag.Bool("json", false, "JSON output format")
		dryRun     = flag.Bool("dry-run", false, "Dry run mode (no changes)")
		version    = flag.Bool("version", false, "Show version information")
		help       = flag.Bool("help", false, "Show help information")
	)
	flag.BoolVar(verbose, "v", false, "Verbose output (shorthand)")
	flag.BoolVar(help, "h", false, "Show help information (shorthand)")
	flag.Parse()

	// Show version
	if *version {
		fmt.Printf("auto-tagger version %s (built on %s, commit %s)\n", Version, BuildDate, GitCommit)
		return
	}

	// Show help
	if *help || len(flag.Args()) == 0 {
		showHelp()
		return
	}

	// Get config path from environment if not specified
	if *configPath == "" {
		if envConfig := os.Getenv("AUTO_TAGGER_CONFIG"); envConfig != "" {
			*configPath = envConfig
		}
	}

	// Set dry-run from environment if flag not set
	if !*dryRun {
		if os.Getenv("AUTO_TAGGER_DRY_RUN") == "true" {
			*dryRun = true
		}
	}

	// Create command interface
	cmdInterface, err := tagging.NewCommandInterface(*configPath, *verbose, *jsonOutput)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	// Override dry-run setting if flag is set
	if *dryRun {
		cmdInterface.AutoTagger.Config.DryRun = true
		cmdInterface.AutoTagger.GitTagger.DryRun = true
		cmdInterface.AutoTagger.ReleaseAutomation.Config.DryRun = true
	}

	// Parse command and arguments
	args := flag.Args()
	command := args[0]
	commandArgs := args[1:]

	// Execute command
	if err := executeCommand(cmdInterface, command, commandArgs); err != nil {
		if !*jsonOutput {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		} else {
			errorOutput := map[string]interface{}{
				"error":   err.Error(),
				"command": command,
				"args":    commandArgs,
			}
			fmt.Fprintf(os.Stderr, "%s\n", mustMarshalJSON(errorOutput))
		}
		os.Exit(1)
	}
}

func executeCommand(cmdInterface *tagging.CommandInterface, command string, args []string) error {
	switch command {
	case "create", "tag":
		return cmdInterface.HandleCreateCommand(args)
	case "validate", "check":
		return cmdInterface.HandleValidateCommand(args)
	case "list", "ls":
		return cmdInterface.HandleListCommand(args)
	case "delete", "rm":
		return cmdInterface.HandleDeleteCommand(args)
	case "changelog", "log":
		return cmdInterface.HandleChangelogCommand(args)
	case "status":
		return cmdInterface.HandleStatusCommand(args)
	case "config":
		return cmdInterface.HandleConfigCommand(args)
	case "policy":
		return cmdInterface.HandlePolicyCommand(args)
	case "help":
		cmdInterface.ShowHelp()
		return nil
	default:
		return fmt.Errorf("unknown command: %s", command)
	}
}

func showHelp() {
	fmt.Printf(`auto-tagger %s - Intelligent Git Tagging System for backlog.md@%s

USAGE:
    auto-tagger [OPTIONS] <COMMAND> [ARGS...]

COMMANDS:
    create [VERSION]      Create a new tag (optionally specify version)
    validate TAG [BRANCH] Validate a tag against policies  
    list                  List all existing tags
    delete TAG            Delete a tag (with policy validation)
    changelog             Generate changelog from Git history
    status                Show auto-tagger status
    config SUBCOMMAND     Configuration management
    policy SUBCOMMAND     Policy management
    help                  Show this help message

CONFIG SUBCOMMANDS:
    show                  Show current configuration
    init                  Initialize default configuration  
    validate              Validate configuration

POLICY SUBCOMMANDS:
    show                  Show current policy
    init                  Initialize default policy
    validate              Validate policy

OPTIONS:
    --config PATH         Configuration file path (default: auto-detect)
    --verbose, -v         Verbose output
    --json                JSON output format
    --dry-run             Dry run mode (no actual changes)
    --version             Show version information
    --help, -h            Show this help message

EXAMPLES:
    # Initialize configuration and policy
    auto-tagger config init
    auto-tagger policy init
    
    # Create tag with automatic version calculation
    auto-tagger create
    
    # Create specific version tag
    auto-tagger create v1.2.3
    
    # Validate tag before creation
    auto-tagger validate v1.2.3 main
    
    # List all tags with details
    auto-tagger list --verbose
    
    # Generate changelog
    auto-tagger changelog
    
    # Check status
    auto-tagger status --json
    
    # Dry run mode
    auto-tagger --dry-run create v1.2.4

ENVIRONMENT VARIABLES:
    AUTO_TAGGER_CONFIG    Configuration file path
    AUTO_TAGGER_DRY_RUN   Set to 'true' for dry run mode
    GITHUB_TOKEN          GitHub API token for releases
    GPG_KEY_ID            GPG key ID for signing tags
    SLACK_WEBHOOK_URL     Slack webhook for notifications
    SMTP_HOST             SMTP server for email notifications

CONFIGURATION:
    The auto-tagger looks for configuration in the following order:
    1. --config flag
    2. AUTO_TAGGER_CONFIG environment variable
    3. ./config/auto-tagger.json
    4. ./.auto-tagger.json
    5. Default configuration

    Policy configuration follows a similar pattern:
    1. ./config/tag-policy.json  
    2. ./.tag-policy.json
    3. Default policy

FILES:
    config/auto-tagger.json   Main configuration file
    config/tag-policy.json    Tagging policy configuration
    CHANGELOG.md              Generated changelog
    scripts/pre-release.sh    Pre-release hook script
    scripts/post-release.sh   Post-release hook script

INTEGRATION:
    - GitHub Releases: Automatic creation with artifacts
    - Slack Notifications: Release announcements  
    - Email Notifications: Team notifications
    - CI/CD Integration: Build triggers and checks
    - Semantic Versioning: Automated version calculation
    - Conventional Commits: Changelog generation

For more information and advanced usage, visit:
https://github.com/conneroisu/backlog.md-flake
`, Version, Version)
}

func mustMarshalJSON(v interface{}) string {
	// This would normally use json.Marshal, simplified for this example
	return fmt.Sprintf(`{"error": "%v"}`, v)
}

// setupLogging configures logging based on verbosity
func setupLogging(verbose bool) {
	// Configure logging level based on verbosity
	if verbose {
		// Enable debug logging
		os.Setenv("LOG_LEVEL", "debug")
	} else {
		// Standard info logging
		os.Setenv("LOG_LEVEL", "info")
	}
}

// validateEnvironment checks required environment variables
func validateEnvironment() error {
	var missing []string

	// Check for Git
	if _, err := os.Stat(".git"); os.IsNotExist(err) {
		return fmt.Errorf("not a git repository (or any of the parent directories)")
	}

	// Warn about optional environment variables
	optionalVars := map[string]string{
		"GITHUB_TOKEN":      "GitHub integration disabled",
		"SLACK_WEBHOOK_URL": "Slack notifications disabled", 
		"GPG_KEY_ID":        "Tag signing disabled",
	}

	for envVar, message := range optionalVars {
		if os.Getenv(envVar) == "" {
			fmt.Fprintf(os.Stderr, "Warning: %s not set - %s\n", envVar, message)
		}
	}

	if len(missing) > 0 {
		return fmt.Errorf("missing required environment variables: %s", strings.Join(missing, ", "))
	}

	return nil
}

// autoDetectConfig attempts to find configuration file automatically
func autoDetectConfig() string {
	candidates := []string{
		"./config/auto-tagger.json",
		"./.auto-tagger.json",
		filepath.Join(os.Getenv("HOME"), ".auto-tagger.json"),
	}

	for _, candidate := range candidates {
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}

	return ""
}

// checkForUpdates checks if a newer version is available (optional feature)
func checkForUpdates() {
	// This would check GitHub releases for newer versions
	// Implementation omitted for brevity
}

// setupCompletions sets up shell completions (future feature)
func setupCompletions() {
	// This would generate shell completions for bash/zsh/fish
	// Implementation omitted for brevity
}

// validateGitRepository ensures we're in a valid Git repository
func validateGitRepository() error {
	// Check if .git exists
	if _, err := os.Stat(".git"); os.IsNotExist(err) {
		return fmt.Errorf("not a git repository")
	}

	// Check if git command is available
	// This would use exec.LookPath("git")
	
	// Check if repository has commits
	// This would use git rev-list --count HEAD

	return nil
}

// initializeApp performs application initialization
func initializeApp(configPath string) error {
	// Set up logging
	setupLogging(false)

	// Validate environment
	if err := validateEnvironment(); err != nil {
		return err
	}

	// Validate git repository
	if err := validateGitRepository(); err != nil {
		return err
	}

	// Auto-detect config if not provided
	if configPath == "" {
		configPath = autoDetectConfig()
	}

	return nil
}

// cleanup performs any necessary cleanup
func cleanup() {
	// This would perform cleanup operations like:
	// - Closing file handles
	// - Clearing temporary files
	// - Saving state
}

// handleSignals sets up signal handling for graceful shutdown
func handleSignals() {
	// This would set up signal handlers for SIGINT, SIGTERM
	// to ensure graceful cleanup
}

// reportUsage sends anonymous usage statistics (opt-in only)
func reportUsage(command string, success bool) {
	// This would report anonymous usage metrics if enabled
	// Implementation omitted for privacy
}