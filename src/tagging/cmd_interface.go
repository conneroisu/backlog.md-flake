package tagging

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/tabwriter"
	"time"
)

// CommandInterface provides a command-line interface for the auto-tagging system
type CommandInterface struct {
	AutoTagger *AutoTagger
	Verbose    bool
	JSON       bool
}

// NewCommandInterface creates a new command interface
func NewCommandInterface(configPath string, verbose, jsonOutput bool) (*CommandInterface, error) {
	autoTagger, err := NewAutoTagger(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize auto-tagger: %w", err)
	}

	return &CommandInterface{
		AutoTagger: autoTagger,
		Verbose:    verbose,
		JSON:       jsonOutput,
	}, nil
}

// HandleCreateCommand handles the create tag command
func (ci *CommandInterface) HandleCreateCommand(args []string) error {
	var forceVersion string
	
	if len(args) > 0 {
		forceVersion = args[0]
	}

	ci.printInfo("Creating new tag...")
	if forceVersion != "" {
		ci.printInfo(fmt.Sprintf("Force version: %s", forceVersion))
	}

	operation, err := ci.AutoTagger.CreateTag(forceVersion)
	if err != nil {
		return fmt.Errorf("failed to create tag: %w", err)
	}

	if ci.JSON {
		return ci.printJSON(operation)
	}

	return ci.printCreateResult(operation)
}

// HandleValidateCommand handles the validate tag command
func (ci *CommandInterface) HandleValidateCommand(args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("tag name is required")
	}

	tagName := args[0]
	var branch string
	if len(args) > 1 {
		branch = args[1]
	} else {
		var err error
		branch, err = ci.AutoTagger.GitTagger.GetCurrentBranch()
		if err != nil {
			return fmt.Errorf("failed to get current branch: %w", err)
		}
	}

	ci.printInfo(fmt.Sprintf("Validating tag: %s on branch: %s", tagName, branch))

	result, err := ci.AutoTagger.ValidateTag(tagName, branch)
	if err != nil {
		return fmt.Errorf("validation failed: %w", err)
	}

	if ci.JSON {
		return ci.printJSON(result)
	}

	return ci.printValidationResult(result)
}

// HandleListCommand handles the list tags command
func (ci *CommandInterface) HandleListCommand(args []string) error {
	ci.printInfo("Listing all tags...")

	tags, err := ci.AutoTagger.ListTags()
	if err != nil {
		return fmt.Errorf("failed to list tags: %w", err)
	}

	if ci.JSON {
		return ci.printJSON(tags)
	}

	return ci.printTagList(tags)
}

// HandleDeleteCommand handles the delete tag command
func (ci *CommandInterface) HandleDeleteCommand(args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("tag name is required")
	}

	tagName := args[0]
	
	ci.printInfo(fmt.Sprintf("Deleting tag: %s", tagName))

	operation, err := ci.AutoTagger.DeleteTag(tagName)
	if err != nil {
		return fmt.Errorf("failed to delete tag: %w", err)
	}

	if ci.JSON {
		return ci.printJSON(operation)
	}

	return ci.printDeleteResult(operation)
}

// HandleChangelogCommand handles the changelog generation command
func (ci *CommandInterface) HandleChangelogCommand(args []string) error {
	ci.printInfo("Generating changelog...")

	if err := ci.AutoTagger.GenerateChangelog(); err != nil {
		return fmt.Errorf("failed to generate changelog: %w", err)
	}

	changelogPath := ci.AutoTagger.Config.ChangelogPath
	if changelogPath == "" {
		changelogPath = filepath.Join(ci.AutoTagger.Config.RepoPath, "CHANGELOG.md")
	}

	ci.printSuccess(fmt.Sprintf("Changelog generated: %s", changelogPath))
	return nil
}

// HandleStatusCommand handles the status command
func (ci *CommandInterface) HandleStatusCommand(args []string) error {
	ci.printInfo("Getting auto-tagger status...")

	status, err := ci.AutoTagger.GetStatus()
	if err != nil {
		return fmt.Errorf("failed to get status: %w", err)
	}

	if ci.JSON {
		return ci.printJSON(status)
	}

	return ci.printStatus(status)
}

// HandleConfigCommand handles configuration commands
func (ci *CommandInterface) HandleConfigCommand(args []string) error {
	if len(args) < 1 {
		return ci.printConfig()
	}

	subCommand := args[0]
	switch subCommand {
	case "show":
		return ci.printConfig()
	case "init":
		return ci.initConfig()
	case "validate":
		return ci.validateConfig()
	default:
		return fmt.Errorf("unknown config subcommand: %s", subCommand)
	}
}

// HandlePolicyCommand handles policy commands
func (ci *CommandInterface) HandlePolicyCommand(args []string) error {
	if len(args) < 1 {
		return ci.printPolicy()
	}

	subCommand := args[0]
	switch subCommand {
	case "show":
		return ci.printPolicy()
	case "init":
		return ci.initPolicy()
	case "validate":
		return ci.validatePolicy()
	default:
		return fmt.Errorf("unknown policy subcommand: %s", subCommand)
	}
}

// Print methods

func (ci *CommandInterface) printCreateResult(operation *TagOperation) error {
	if operation.Status == "failed" {
		ci.printError(fmt.Sprintf("Tag creation failed: %s", operation.Error))
		return nil
	}

	ci.printSuccess(fmt.Sprintf("Tag created successfully: %s", operation.TagName))
	
	if ci.Verbose && operation.Result != nil {
		fmt.Println()
		fmt.Println("Operation Details:")
		fmt.Printf("  Tag Created: %v\n", operation.Result.TagCreated)
		fmt.Printf("  Changelog Updated: %v\n", operation.Result.ChangelogUpdated)
		
		if operation.Result.GitHubRelease != nil {
			fmt.Printf("  GitHub Release: %s\n", operation.Result.GitHubRelease.HTMLURL)
		}
		
		if len(operation.Result.ArtifactsUploaded) > 0 {
			fmt.Printf("  Artifacts Uploaded: %s\n", strings.Join(operation.Result.ArtifactsUploaded, ", "))
		}
		
		if len(operation.Result.NotificationsSent) > 0 {
			fmt.Printf("  Notifications Sent: %s\n", strings.Join(operation.Result.NotificationsSent, ", "))
		}

		if operation.ValidationResult != nil {
			fmt.Printf("  Policy Violations: %d\n", len(operation.ValidationResult.Violations))
			fmt.Printf("  Policy Warnings: %d\n", len(operation.ValidationResult.Warnings))
		}
	}

	return nil
}

func (ci *CommandInterface) printValidationResult(result *PolicyResult) error {
	if result.Valid {
		ci.printSuccess("Tag validation passed")
	} else {
		ci.printError("Tag validation failed")
	}

	fmt.Println()
	fmt.Printf("Summary:\n")
	fmt.Printf("  Total Rules: %d\n", result.Summary.TotalRules)
	fmt.Printf("  Passed Rules: %d\n", result.Summary.PassedRules)
	fmt.Printf("  Failed Rules: %d\n", result.Summary.FailedRules)
	fmt.Printf("  Critical Issues: %d\n", result.Summary.CriticalIssues)
	fmt.Printf("  Warning Issues: %d\n", result.Summary.WarningIssues)

	if len(result.Violations) > 0 {
		fmt.Println()
		fmt.Println("Violations:")
		for _, violation := range result.Violations {
			fmt.Printf("  [%s] %s: %s\n", violation.Severity, violation.Rule, violation.Message)
			if violation.Suggestion != "" && ci.Verbose {
				fmt.Printf("    Suggestion: %s\n", violation.Suggestion)
			}
		}
	}

	if len(result.Warnings) > 0 {
		fmt.Println()
		fmt.Println("Warnings:")
		for _, warning := range result.Warnings {
			fmt.Printf("  [%s] %s: %s\n", warning.Severity, warning.Rule, warning.Message)
		}
	}

	return nil
}

func (ci *CommandInterface) printTagList(tags []*TagInfo) error {
	if len(tags) == 0 {
		fmt.Println("No tags found")
		return nil
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "NAME\tDATE\tAUTHOR\tMESSAGE")
	fmt.Fprintln(w, "----\t----\t------\t-------")

	for _, tag := range tags {
		date := tag.Date.Format("2006-01-02")
		message := strings.Split(tag.Message, "\n")[0] // First line only
		if len(message) > 50 {
			message = message[:47] + "..."
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\n", tag.Name, date, tag.Author, message)
	}

	return w.Flush()
}

func (ci *CommandInterface) printDeleteResult(operation *TagOperation) error {
	if operation.Status == "failed" {
		ci.printError(fmt.Sprintf("Tag deletion failed: %s", operation.Error))
		return nil
	}

	ci.printSuccess(fmt.Sprintf("Tag deleted successfully: %s", operation.TagName))
	return nil
}

func (ci *CommandInterface) printStatus(status map[string]interface{}) error {
	fmt.Println("Auto-Tagger Status:")
	fmt.Printf("  Repository: %s\n", status["repository"])
	fmt.Printf("  Dry Run: %v\n", status["dry_run"])
	fmt.Printf("  GitHub Enabled: %v\n", status["github_enabled"])
	fmt.Printf("  Policy Valid: %v\n", status["policy_valid"])

	if latestTag, ok := status["latest_tag"].(map[string]interface{}); ok && latestTag != nil {
		fmt.Println()
		fmt.Println("Latest Tag:")
		fmt.Printf("  Name: %s\n", latestTag["name"])
		fmt.Printf("  Date: %s\n", latestTag["date"])
		fmt.Printf("  Author: %s\n", latestTag["author"])
	}

	if violations, ok := status["policy_violations"].([]PolicyViolation); ok && len(violations) > 0 {
		fmt.Println()
		fmt.Println("Policy Violations:")
		for _, violation := range violations {
			fmt.Printf("  [%s] %s: %s\n", violation.Severity, violation.Rule, violation.Message)
		}
	}

	return nil
}

func (ci *CommandInterface) printConfig() error {
	if ci.JSON {
		return ci.printJSON(ci.AutoTagger.Config)
	}

	fmt.Println("Auto-Tagger Configuration:")
	fmt.Printf("  Repository Path: %s\n", ci.AutoTagger.Config.RepoPath)
	fmt.Printf("  Dry Run: %v\n", ci.AutoTagger.Config.DryRun)
	fmt.Printf("  Config Path: %s\n", ci.AutoTagger.Config.ConfigPath)
	fmt.Printf("  Changelog Path: %s\n", ci.AutoTagger.Config.ChangelogPath)
	fmt.Printf("  Policy Path: %s\n", ci.AutoTagger.Config.PolicyPath)
	fmt.Printf("  Auto Push: %v\n", ci.AutoTagger.Config.AutoPush)
	fmt.Printf("  Create GitHub Release: %v\n", ci.AutoTagger.Config.CreateGitHubRelease)
	fmt.Printf("  Sign Tags: %v\n", ci.AutoTagger.Config.SignTags)
	fmt.Printf("  Tag Prefix: %s\n", ci.AutoTagger.Config.TagPrefix)
	fmt.Printf("  Version Strategy: %s\n", ci.AutoTagger.Config.VersionStrategy)
	fmt.Printf("  Required Branches: %s\n", strings.Join(ci.AutoTagger.Config.RequiredBranches, ", "))

	return nil
}

func (ci *CommandInterface) printPolicy() error {
	if ci.JSON {
		return ci.printJSON(ci.AutoTagger.PolicyValidator.Policy)
	}

	policy := ci.AutoTagger.PolicyValidator.Policy
	fmt.Println("Tagging Policy:")
	fmt.Printf("  Enforcement: %s\n", policy.Enforcement)
	fmt.Printf("  Allowed Branches: %s\n", strings.Join(policy.AllowedBranches, ", "))
	fmt.Printf("  Required Checks: %s\n", strings.Join(policy.RequiredChecks, ", "))

	fmt.Println()
	fmt.Printf("Rules (%d):\n", len(policy.Rules))
	for _, rule := range policy.Rules {
		status := "disabled"
		if rule.Enabled {
			status = "enabled"
		}
		fmt.Printf("  [%s] %s (%s): %s\n", rule.Severity, rule.Name, status, rule.Description)
	}

	return nil
}

func (ci *CommandInterface) initConfig() error {
	configPath := filepath.Join(ci.AutoTagger.Config.RepoPath, ".auto-tagger.json")
	ci.AutoTagger.Config.ConfigPath = configPath

	if err := ci.AutoTagger.SaveConfig(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	ci.printSuccess(fmt.Sprintf("Configuration initialized: %s", configPath))
	return nil
}

func (ci *CommandInterface) initPolicy() error {
	policyPath := ci.AutoTagger.Config.PolicyPath
	if policyPath == "" {
		policyPath = filepath.Join(ci.AutoTagger.Config.RepoPath, ".tag-policy.json")
		ci.AutoTagger.Config.PolicyPath = policyPath
	}

	if err := ci.AutoTagger.PolicyValidator.SavePolicy(); err != nil {
		return fmt.Errorf("failed to save policy: %w", err)
	}

	ci.printSuccess(fmt.Sprintf("Policy initialized: %s", policyPath))
	return nil
}

func (ci *CommandInterface) validateConfig() error {
	if err := ci.AutoTagger.ReleaseAutomation.ValidateRelease(); err != nil {
		ci.printError(fmt.Sprintf("Configuration validation failed: %s", err.Error()))
		return nil
	}

	ci.printSuccess("Configuration is valid")
	return nil
}

func (ci *CommandInterface) validatePolicy() error {
	violations := ci.AutoTagger.PolicyValidator.ValidatePolicy()
	
	if len(violations) == 0 {
		ci.printSuccess("Policy is valid")
		return nil
	}

	ci.printError("Policy validation failed")
	fmt.Println()
	fmt.Println("Violations:")
	for _, violation := range violations {
		fmt.Printf("  [%s] %s: %s\n", violation.Severity, violation.Rule, violation.Message)
	}

	return nil
}

// Utility methods

func (ci *CommandInterface) printJSON(data interface{}) error {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetIndent("", "  ")
	return encoder.Encode(data)
}

func (ci *CommandInterface) printInfo(message string) {
	if !ci.JSON {
		fmt.Printf("ℹ %s\n", message)
	}
}

func (ci *CommandInterface) printSuccess(message string) {
	if !ci.JSON {
		fmt.Printf("✅ %s\n", message)
	}
}

func (ci *CommandInterface) printError(message string) {
	if !ci.JSON {
		fmt.Printf("❌ %s\n", message)
	}
}

func (ci *CommandInterface) printWarning(message string) {
	if !ci.JSON {
		fmt.Printf("⚠️ %s\n", message)
	}
}

// ShowHelp displays help information
func (ci *CommandInterface) ShowHelp() {
	fmt.Println(`Auto-Tagger - Intelligent Git Tagging System

USAGE:
    auto-tagger [OPTIONS] <COMMAND> [ARGS...]

COMMANDS:
    create [VERSION]    Create a new tag (optionally specify version)
    validate TAG [BRANCH] Validate a tag against policies
    list               List all existing tags
    delete TAG         Delete a tag
    changelog          Generate changelog from Git history
    status             Show auto-tagger status
    config SUBCOMMAND  Configuration management
    policy SUBCOMMAND  Policy management
    help               Show this help message

CONFIG SUBCOMMANDS:
    show               Show current configuration
    init               Initialize default configuration
    validate           Validate configuration

POLICY SUBCOMMANDS:
    show               Show current policy
    init               Initialize default policy
    validate           Validate policy

OPTIONS:
    --config PATH      Configuration file path
    --verbose, -v      Verbose output
    --json             JSON output format
    --dry-run          Dry run mode (no changes)
    --help, -h         Show help

EXAMPLES:
    auto-tagger create                    # Create tag with auto-version
    auto-tagger create v1.2.3             # Create specific version tag
    auto-tagger validate v1.2.3 main      # Validate tag on branch
    auto-tagger list                      # List all tags
    auto-tagger config init               # Initialize configuration
    auto-tagger policy show               # Show tagging policy

ENVIRONMENT VARIABLES:
    GITHUB_TOKEN       GitHub API token for releases
    GPG_KEY_ID         GPG key ID for signing tags
    AUTO_TAGGER_CONFIG Configuration file path`)
}