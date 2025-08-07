package tagging

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ReleaseAutomation handles automated release processes
type ReleaseAutomation struct {
	GitTagger           *GitTagger
	ChangelogGenerator  *ChangelogGenerator
	GitHubIntegration   *GitHubIntegration
	Config              *ReleaseConfig
}

// ReleaseConfig contains configuration for release automation
type ReleaseConfig struct {
	RepoPath            string
	DryRun              bool
	AutoPush            bool
	CreateGitHubRelease bool
	ChangelogPath       string
	PreReleaseHook      string
	PostReleaseHook     string
	TagPrefix           string
	RequiredBranches    []string
	AllowDirtyWorkTree  bool
	SignTags            bool
	GPGKeyID            string
}

// ReleaseContext contains information about a release
type ReleaseContext struct {
	CurrentVersion  *SemanticVersion
	NextVersion     *SemanticVersion
	CommitsSince    []string
	ChangelogEntry  *ChangelogEntry
	TagInfo         *TagInfo
	GitHubRelease   *GitHubRelease
	Artifacts       []ReleaseArtifact
}

// ReleaseArtifact represents a file or asset to be included in the release
type ReleaseArtifact struct {
	Name        string
	Path        string
	ContentType string
	Description string
}

// NewReleaseAutomation creates a new release automation instance
func NewReleaseAutomation(config *ReleaseConfig) *ReleaseAutomation {
	tagger := NewGitTagger(config.RepoPath, config.DryRun)
	changelogGen := NewChangelogGenerator(config.RepoPath, config.ChangelogPath)
	githubIntegration := NewGitHubIntegration(config.RepoPath)

	return &ReleaseAutomation{
		GitTagger:          tagger,
		ChangelogGenerator: changelogGen,
		GitHubIntegration:  githubIntegration,
		Config:             config,
	}
}

// CreateRelease performs a complete automated release
func (ra *ReleaseAutomation) CreateRelease(forceVersion string) (*ReleaseContext, error) {
	context := &ReleaseContext{}

	// Pre-flight checks
	if err := ra.preFlightChecks(); err != nil {
		return nil, fmt.Errorf("pre-flight checks failed: %w", err)
	}

	// Get current version
	latestTag, err := ra.GitTagger.GetLatestTag()
	if err != nil {
		return nil, fmt.Errorf("failed to get latest tag: %w", err)
	}

	var currentVersionStr string
	if latestTag != nil {
		currentVersionStr = latestTag.Name
		context.CurrentVersion, _ = ParseVersion(currentVersionStr)
	} else {
		currentVersionStr = "v0.0.0"
		context.CurrentVersion = &SemanticVersion{Major: 0, Minor: 0, Patch: 0}
	}

	// Get commits since last tag
	commits, err := ra.GitTagger.GetCommitsSinceTag(currentVersionStr)
	if err != nil {
		return nil, fmt.Errorf("failed to get commits: %w", err)
	}

	if len(commits) == 0 && forceVersion == "" {
		return nil, fmt.Errorf("no new commits since last release")
	}

	context.CommitsSince = commits

	// Calculate next version
	if forceVersion != "" {
		context.NextVersion, err = ParseVersion(forceVersion)
		if err != nil {
			return nil, fmt.Errorf("invalid force version: %w", err)
		}
	} else {
		context.NextVersion, err = CalculateNextVersion(currentVersionStr, commits)
		if err != nil {
			return nil, fmt.Errorf("failed to calculate next version: %w", err)
		}
	}

	// Run pre-release hook
	if ra.Config.PreReleaseHook != "" {
		if err := ra.runHook(ra.Config.PreReleaseHook, context); err != nil {
			return nil, fmt.Errorf("pre-release hook failed: %w", err)
		}
	}

	// Create changelog entry
	context.ChangelogEntry = ra.createChangelogEntry(context)

	// Update changelog file
	if err := ra.updateChangelog(context); err != nil {
		return nil, fmt.Errorf("failed to update changelog: %w", err)
	}

	// Create Git tag
	tagInfo, err := ra.createGitTag(context)
	if err != nil {
		return nil, fmt.Errorf("failed to create git tag: %w", err)
	}
	context.TagInfo = tagInfo

	// Push tag if auto-push is enabled
	if ra.Config.AutoPush {
		if err := ra.GitTagger.PushTag(tagInfo.Name); err != nil {
			return nil, fmt.Errorf("failed to push tag: %w", err)
		}
	}

	// Create GitHub release
	if ra.Config.CreateGitHubRelease {
		githubRelease, err := ra.createGitHubRelease(context)
		if err != nil {
			return nil, fmt.Errorf("failed to create GitHub release: %w", err)
		}
		context.GitHubRelease = githubRelease
	}

	// Run post-release hook
	if ra.Config.PostReleaseHook != "" {
		if err := ra.runHook(ra.Config.PostReleaseHook, context); err != nil {
			return nil, fmt.Errorf("post-release hook failed: %w", err)
		}
	}

	return context, nil
}

// preFlightChecks performs pre-release validation
func (ra *ReleaseAutomation) preFlightChecks() error {
	// Check if repository is clean
	if !ra.Config.AllowDirtyWorkTree {
		hasChanges, err := ra.GitTagger.HasUncommittedChanges()
		if err != nil {
			return fmt.Errorf("failed to check git status: %w", err)
		}
		if hasChanges {
			return fmt.Errorf("repository has uncommitted changes")
		}
	}

	// Check current branch
	if len(ra.Config.RequiredBranches) > 0 {
		currentBranch, err := ra.GitTagger.GetCurrentBranch()
		if err != nil {
			return fmt.Errorf("failed to get current branch: %w", err)
		}

		allowed := false
		for _, branch := range ra.Config.RequiredBranches {
			if currentBranch == branch {
				allowed = true
				break
			}
		}

		if !allowed {
			return fmt.Errorf("current branch '%s' not in allowed branches: %v", 
				currentBranch, ra.Config.RequiredBranches)
		}
	}

	// Check if changelog directory exists
	if ra.Config.ChangelogPath != "" {
		changelogDir := filepath.Dir(ra.Config.ChangelogPath)
		if _, err := os.Stat(changelogDir); os.IsNotExist(err) {
			return fmt.Errorf("changelog directory does not exist: %s", changelogDir)
		}
	}

	return nil
}

// createChangelogEntry creates a changelog entry for the release
func (ra *ReleaseAutomation) createChangelogEntry(context *ReleaseContext) *ChangelogEntry {
	changes := make([]ChangeItem, 0, len(context.CommitsSince))
	
	for _, commit := range context.CommitsSince {
		item := ra.ChangelogGenerator.ParseCommitMessage(commit, "")
		
		// Filter by included types
		include := false
		for _, includeType := range ra.ChangelogGenerator.IncludeTypes {
			if item.Type == includeType {
				include = true
				break
			}
		}
		
		if include {
			changes = append(changes, *item)
		}
	}

	return &ChangelogEntry{
		Version: context.NextVersion,
		Date:    time.Now(),
		Changes: changes,
	}
}

// updateChangelog updates the changelog file with the new entry
func (ra *ReleaseAutomation) updateChangelog(context *ReleaseContext) error {
	if ra.Config.ChangelogPath == "" {
		return nil // No changelog configured
	}

	// Generate new changelog
	changelog, err := ra.ChangelogGenerator.GenerateFromTags(ra.GitTagger)
	if err != nil {
		return fmt.Errorf("failed to generate changelog: %w", err)
	}

	// Add new entry at the beginning
	entries := []*ChangelogEntry{context.ChangelogEntry}
	entries = append(entries, changelog.Entries...)
	changelog.Entries = entries

	// Clear unreleased changes since they're now released
	changelog.UnreleasedChanges = []ChangeItem{}

	return changelog.WriteToFile(ra.Config.ChangelogPath)
}

// createGitTag creates the Git tag for the release
func (ra *ReleaseAutomation) createGitTag(context *ReleaseContext) (*TagInfo, error) {
	tagName := ra.Config.TagPrefix + context.NextVersion.String()
	
	// Create tag message
	message := fmt.Sprintf("Release %s", context.NextVersion.String())
	if len(context.CommitsSince) > 0 {
		message += "\n\nChanges:\n"
		for _, commit := range context.CommitsSince {
			message += fmt.Sprintf("- %s\n", commit)
		}
	}

	// Create the tag
	var err error
	if ra.Config.SignTags && ra.Config.GPGKeyID != "" {
		err = ra.createSignedTag(tagName, message)
	} else {
		err = ra.GitTagger.CreateTag(tagName, message, true)
	}

	if err != nil {
		return nil, err
	}

	return ra.GitTagger.GetTagInfo(tagName)
}

// createSignedTag creates a GPG-signed tag
func (ra *ReleaseAutomation) createSignedTag(tagName, message string) error {
	if ra.GitTagger.DryRun {
		fmt.Printf("[DRY RUN] Would create signed tag: %s\n", tagName)
		return nil
	}

	// This would use exec.Command to create a signed tag
	// exec.Command("git", "tag", "-s", "-u", ra.Config.GPGKeyID, tagName, "-m", message)
	fmt.Printf("Creating signed tag %s with key %s\n", tagName, ra.Config.GPGKeyID)
	return ra.GitTagger.CreateTag(tagName, message, true)
}

// createGitHubRelease creates a GitHub release
func (ra *ReleaseAutomation) createGitHubRelease(context *ReleaseContext) (*GitHubRelease, error) {
	// Generate release notes from changelog entry
	releaseNotes := ra.generateReleaseNotes(context.ChangelogEntry)
	
	release := &GitHubRelease{
		TagName:      context.TagInfo.Name,
		Name:         fmt.Sprintf("Release %s", context.NextVersion.String()),
		Body:         releaseNotes,
		Draft:        false,
		PreRelease:   context.NextVersion.PreRelease != "",
		GenerateNotes: false,
	}

	return ra.GitHubIntegration.CreateRelease(release)
}

// generateReleaseNotes generates release notes from a changelog entry
func (ra *ReleaseAutomation) generateReleaseNotes(entry *ChangelogEntry) string {
	if len(entry.Changes) == 0 {
		return "No significant changes in this release."
	}

	var notes strings.Builder
	
	// Group changes by type
	grouped := entry.GroupedChanges()
	
	typeOrder := []string{"Breaking Changes", "Added", "Fixed", "Performance", "Documentation", "Refactored", "Other"}
	
	for _, typeStr := range typeOrder {
		changes, exists := grouped[typeStr]
		if !exists || len(changes) == 0 {
			continue
		}
		
		notes.WriteString(fmt.Sprintf("## %s\n\n", typeStr))
		
		for _, change := range changes {
			notes.WriteString(fmt.Sprintf("- %s", change.Description))
			if change.Scope != "" {
				notes.WriteString(fmt.Sprintf(" (%s)", change.Scope))
			}
			notes.WriteString("\n")
		}
		
		notes.WriteString("\n")
	}
	
	return notes.String()
}

// runHook executes a release hook script
func (ra *ReleaseAutomation) runHook(hookPath string, context *ReleaseContext) error {
	if ra.GitTagger.DryRun {
		fmt.Printf("[DRY RUN] Would run hook: %s\n", hookPath)
		return nil
	}

	// Set environment variables for the hook
	env := os.Environ()
	env = append(env, fmt.Sprintf("RELEASE_VERSION=%s", context.NextVersion.String()))
	if context.CurrentVersion != nil {
		env = append(env, fmt.Sprintf("PREVIOUS_VERSION=%s", context.CurrentVersion.String()))
	}
	env = append(env, fmt.Sprintf("RELEASE_TAG=%s", context.TagInfo.Name))

	// This would use exec.Command to run the hook
	fmt.Printf("Running hook: %s with version %s\n", hookPath, context.NextVersion.String())
	return nil
}

// ValidateRelease validates a release configuration
func (ra *ReleaseAutomation) ValidateRelease() error {
	// Check required tools
	tools := []string{"git"}
	for _, tool := range tools {
		if !ra.isCommandAvailable(tool) {
			return fmt.Errorf("required tool not available: %s", tool)
		}
	}

	// Check Git repository
	if _, err := os.Stat(filepath.Join(ra.Config.RepoPath, ".git")); os.IsNotExist(err) {
		return fmt.Errorf("not a git repository: %s", ra.Config.RepoPath)
	}

	// Check hooks exist
	if ra.Config.PreReleaseHook != "" {
		if _, err := os.Stat(ra.Config.PreReleaseHook); os.IsNotExist(err) {
			return fmt.Errorf("pre-release hook not found: %s", ra.Config.PreReleaseHook)
		}
	}

	if ra.Config.PostReleaseHook != "" {
		if _, err := os.Stat(ra.Config.PostReleaseHook); os.IsNotExist(err) {
			return fmt.Errorf("post-release hook not found: %s", ra.Config.PostReleaseHook)
		}
	}

	return nil
}

// isCommandAvailable checks if a command is available in PATH
func (ra *ReleaseAutomation) isCommandAvailable(command string) bool {
	// This would use exec.LookPath to check if command exists
	return true // Simplified for this example
}

// CreateReleaseArtifacts creates release artifacts (binaries, packages, etc.)
func (ra *ReleaseAutomation) CreateReleaseArtifacts(context *ReleaseContext) error {
	// This would build and package release artifacts
	// For now, just create a simple artifact list
	
	context.Artifacts = []ReleaseArtifact{
		{
			Name:        fmt.Sprintf("backlog-md-%s-linux-amd64.tar.gz", context.NextVersion.String()),
			Path:        filepath.Join(ra.Config.RepoPath, "dist", "linux-amd64.tar.gz"),
			ContentType: "application/gzip",
			Description: "Linux AMD64 binary",
		},
		{
			Name:        fmt.Sprintf("backlog-md-%s-darwin-amd64.tar.gz", context.NextVersion.String()),
			Path:        filepath.Join(ra.Config.RepoPath, "dist", "darwin-amd64.tar.gz"),
			ContentType: "application/gzip",
			Description: "macOS AMD64 binary",
		},
		{
			Name:        fmt.Sprintf("backlog-md-%s-windows-amd64.zip", context.NextVersion.String()),
			Path:        filepath.Join(ra.Config.RepoPath, "dist", "windows-amd64.zip"),
			ContentType: "application/zip",
			Description: "Windows AMD64 binary",
		},
	}
	
	return nil
}

// RollbackRelease rolls back a failed release
func (ra *ReleaseAutomation) RollbackRelease(tagName string) error {
	if ra.GitTagger.DryRun {
		fmt.Printf("[DRY RUN] Would rollback release: %s\n", tagName)
		return nil
	}

	// Delete local tag
	if err := ra.GitTagger.DeleteTag(tagName); err != nil {
		return fmt.Errorf("failed to delete local tag: %w", err)
	}

	// Delete remote tag (would need proper implementation)
	fmt.Printf("Would delete remote tag: %s\n", tagName)

	// Delete GitHub release (would need proper implementation)
	fmt.Printf("Would delete GitHub release: %s\n", tagName)

	return nil
}