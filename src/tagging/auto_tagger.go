package tagging

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// AutoTagger orchestrates the entire auto-tagging system
type AutoTagger struct {
	Config              *AutoTaggerConfig
	GitTagger           *GitTagger
	ChangelogGenerator  *ChangelogGenerator
	ReleaseAutomation   *ReleaseAutomation
	GitHubIntegration   *GitHubIntegration
	PolicyValidator     *PolicyValidator
}

// AutoTaggerConfig contains configuration for the auto-tagging system
type AutoTaggerConfig struct {
	RepoPath            string            `json:"repo_path"`
	DryRun              bool              `json:"dry_run"`
	ConfigPath          string            `json:"config_path"`
	ChangelogPath       string            `json:"changelog_path"`
	PolicyPath          string            `json:"policy_path"`
	AutoPush            bool              `json:"auto_push"`
	CreateGitHubRelease bool              `json:"create_github_release"`
	SignTags            bool              `json:"sign_tags"`
	GPGKeyID            string            `json:"gpg_key_id"`
	RequiredBranches    []string          `json:"required_branches"`
	AllowDirtyWorkTree  bool              `json:"allow_dirty_worktree"`
	PreReleaseHook      string            `json:"pre_release_hook"`
	PostReleaseHook     string            `json:"post_release_hook"`
	TagPrefix           string            `json:"tag_prefix"`
	VersionStrategy     string            `json:"version_strategy"` // "auto", "manual", "ci"
	NotificationChannels []string         `json:"notification_channels"`
	Environment         map[string]string `json:"environment"`
	Integrations        IntegrationConfig `json:"integrations"`
}

// IntegrationConfig contains integration-specific settings
type IntegrationConfig struct {
	GitHub GitHubConfig `json:"github"`
	Slack  SlackConfig  `json:"slack"`
	Email  EmailConfig  `json:"email"`
	CI     CIConfig     `json:"ci"`
}

// GitHubConfig contains GitHub-specific settings
type GitHubConfig struct {
	Token              string   `json:"token"`
	Owner              string   `json:"owner"`
	Repo               string   `json:"repo"`
	AutoRelease        bool     `json:"auto_release"`
	ReleaseTemplate    string   `json:"release_template"`
	UploadArtifacts    bool     `json:"upload_artifacts"`
	ArtifactPatterns   []string `json:"artifact_patterns"`
	GenerateNotes      bool     `json:"generate_notes"`
	MarkAsLatest       bool     `json:"mark_as_latest"`
}

// SlackConfig contains Slack notification settings
type SlackConfig struct {
	WebhookURL string `json:"webhook_url"`
	Channel    string `json:"channel"`
	Username   string `json:"username"`
	IconEmoji  string `json:"icon_emoji"`
}

// EmailConfig contains email notification settings
type EmailConfig struct {
	SMTPHost     string   `json:"smtp_host"`
	SMTPPort     int      `json:"smtp_port"`
	SMTPUser     string   `json:"smtp_user"`
	SMTPPassword string   `json:"smtp_password"`
	From         string   `json:"from"`
	To           []string `json:"to"`
	Subject      string   `json:"subject"`
}

// CIConfig contains CI/CD integration settings
type CIConfig struct {
	Provider        string            `json:"provider"` // "github", "gitlab", "jenkins"
	RequiredChecks  []string          `json:"required_checks"`
	WaitForChecks   bool              `json:"wait_for_checks"`
	CheckTimeout    int               `json:"check_timeout"`
	TriggerBuilds   bool              `json:"trigger_builds"`
	BuildParameters map[string]string `json:"build_parameters"`
}

// TagOperation represents a tagging operation
type TagOperation struct {
	ID              string              `json:"id"`
	Type            string              `json:"type"` // "create", "delete", "update"
	TagName         string              `json:"tag_name"`
	ForceVersion    string              `json:"force_version,omitempty"`
	Branch          string              `json:"branch"`
	Message         string              `json:"message"`
	Status          string              `json:"status"` // "pending", "running", "completed", "failed"
	StartTime       time.Time           `json:"start_time"`
	EndTime         *time.Time          `json:"end_time,omitempty"`
	Error           string              `json:"error,omitempty"`
	Result          *TagOperationResult `json:"result,omitempty"`
	ValidationResult *PolicyResult      `json:"validation_result,omitempty"`
}

// TagOperationResult contains the result of a tagging operation
type TagOperationResult struct {
	TagCreated      bool           `json:"tag_created"`
	TagInfo         *TagInfo       `json:"tag_info,omitempty"`
	ChangelogUpdated bool          `json:"changelog_updated"`
	GitHubRelease   *GitHubRelease `json:"github_release,omitempty"`
	ArtifactsUploaded []string     `json:"artifacts_uploaded"`
	NotificationsSent []string     `json:"notifications_sent"`
}

// NewAutoTagger creates a new auto-tagger instance
func NewAutoTagger(configPath string) (*AutoTagger, error) {
	config, err := LoadAutoTaggerConfig(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %w", err)
	}

	return NewAutoTaggerWithConfig(config)
}

// NewAutoTaggerWithConfig creates a new auto-tagger with the provided config
func NewAutoTaggerWithConfig(config *AutoTaggerConfig) (*AutoTagger, error) {
	// Initialize components
	gitTagger := NewGitTagger(config.RepoPath, config.DryRun)
	changelogGen := NewChangelogGenerator(config.RepoPath, config.ChangelogPath)
	githubIntegration := NewGitHubIntegration(config.RepoPath)

	// Initialize policy validator
	policyValidator, err := NewPolicyValidator(config.PolicyPath)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize policy validator: %w", err)
	}

	// Create release config
	releaseConfig := &ReleaseConfig{
		RepoPath:            config.RepoPath,
		DryRun:              config.DryRun,
		AutoPush:            config.AutoPush,
		CreateGitHubRelease: config.CreateGitHubRelease,
		ChangelogPath:       config.ChangelogPath,
		PreReleaseHook:      config.PreReleaseHook,
		PostReleaseHook:     config.PostReleaseHook,
		TagPrefix:           config.TagPrefix,
		RequiredBranches:    config.RequiredBranches,
		AllowDirtyWorkTree:  config.AllowDirtyWorkTree,
		SignTags:            config.SignTags,
		GPGKeyID:            config.GPGKeyID,
	}

	releaseAutomation := NewReleaseAutomation(releaseConfig)

	return &AutoTagger{
		Config:              config,
		GitTagger:           gitTagger,
		ChangelogGenerator:  changelogGen,
		ReleaseAutomation:   releaseAutomation,
		GitHubIntegration:   githubIntegration,
		PolicyValidator:     policyValidator,
	}, nil
}

// CreateTag creates a new tag with full automation
func (at *AutoTagger) CreateTag(forceVersion string) (*TagOperation, error) {
	operation := &TagOperation{
		ID:           generateOperationID(),
		Type:         "create",
		ForceVersion: forceVersion,
		Status:       "pending",
		StartTime:    time.Now(),
	}

	// Get current branch
	branch, err := at.GitTagger.GetCurrentBranch()
	if err != nil {
		return at.failOperation(operation, fmt.Errorf("failed to get current branch: %w", err))
	}
	operation.Branch = branch

	// Start operation
	operation.Status = "running"

	// Step 1: Validate policy
	validationResult := at.PolicyValidator.ValidateTag(forceVersion, branch, "", at.GitTagger)
	operation.ValidationResult = validationResult

	if !validationResult.Approved {
		return at.failOperation(operation, fmt.Errorf("policy validation failed: %d violations", len(validationResult.Violations)))
	}

	// Step 2: Create release
	context, err := at.ReleaseAutomation.CreateRelease(forceVersion)
	if err != nil {
		return at.failOperation(operation, fmt.Errorf("failed to create release: %w", err))
	}

	// Step 3: Populate operation result
	operation.TagName = context.NextVersion.String()
	operation.Result = &TagOperationResult{
		TagCreated:        context.TagInfo != nil,
		TagInfo:           context.TagInfo,
		ChangelogUpdated:  context.ChangelogEntry != nil,
		GitHubRelease:     context.GitHubRelease,
		ArtifactsUploaded: []string{},
		NotificationsSent: []string{},
	}

	// Step 4: Send notifications
	if err := at.sendNotifications(operation, "tag_created"); err != nil {
		// Don't fail the operation for notification errors, just log
		fmt.Printf("Warning: failed to send notifications: %v\n", err)
	}

	// Complete operation
	now := time.Now()
	operation.EndTime = &now
	operation.Status = "completed"

	return operation, nil
}

// ValidateTag validates a tag against policies without creating it
func (at *AutoTagger) ValidateTag(tagName, branch string) (*PolicyResult, error) {
	return at.PolicyValidator.ValidateTag(tagName, branch, "", at.GitTagger), nil
}

// ListTags lists all tags with their information
func (at *AutoTagger) ListTags() ([]*TagInfo, error) {
	return at.GitTagger.GetAllTags()
}

// GetLatestTag gets the latest tag
func (at *AutoTagger) GetLatestTag() (*TagInfo, error) {
	return at.GitTagger.GetLatestTag()
}

// DeleteTag deletes a tag (with policy validation)
func (at *AutoTagger) DeleteTag(tagName string) (*TagOperation, error) {
	operation := &TagOperation{
		ID:        generateOperationID(),
		Type:      "delete",
		TagName:   tagName,
		Status:    "pending",
		StartTime: time.Now(),
	}

	// Check protection policy
	if at.isProtectedTag(tagName) {
		return at.failOperation(operation, fmt.Errorf("tag '%s' is protected and cannot be deleted", tagName))
	}

	operation.Status = "running"

	// Delete the tag
	if err := at.GitTagger.DeleteTag(tagName); err != nil {
		return at.failOperation(operation, fmt.Errorf("failed to delete tag: %w", err))
	}

	// Send notifications
	if err := at.sendNotifications(operation, "tag_deleted"); err != nil {
		fmt.Printf("Warning: failed to send notifications: %v\n", err)
	}

	// Complete operation
	now := time.Now()
	operation.EndTime = &now
	operation.Status = "completed"

	return operation, nil
}

// GenerateChangelog generates a changelog from Git history
func (at *AutoTagger) GenerateChangelog() error {
	return at.ChangelogGenerator.GenerateChangelogFile()
}

// UpdatePolicy updates the tagging policy
func (at *AutoTagger) UpdatePolicy(updates map[string]interface{}) error {
	// This would update policy settings based on the updates map
	return at.PolicyValidator.SavePolicy()
}

// GetStatus returns the current status of the auto-tagger
func (at *AutoTagger) GetStatus() (map[string]interface{}, error) {
	latestTag, _ := at.GetLatestTag()
	
	status := map[string]interface{}{
		"repository":     at.Config.RepoPath,
		"dry_run":        at.Config.DryRun,
		"latest_tag":     nil,
		"policy_valid":   true,
		"github_enabled": at.Config.CreateGitHubRelease,
	}

	if latestTag != nil {
		status["latest_tag"] = map[string]interface{}{
			"name":    latestTag.Name,
			"date":    latestTag.Date.Format(time.RFC3339),
			"author":  latestTag.Author,
		}
	}

	// Validate policy
	violations := at.PolicyValidator.ValidatePolicy()
	if len(violations) > 0 {
		status["policy_valid"] = false
		status["policy_violations"] = violations
	}

	return status, nil
}

// failOperation marks an operation as failed
func (at *AutoTagger) failOperation(operation *TagOperation, err error) (*TagOperation, error) {
	now := time.Now()
	operation.EndTime = &now
	operation.Status = "failed"
	operation.Error = err.Error()
	return operation, err
}

// isProtectedTag checks if a tag is protected
func (at *AutoTagger) isProtectedTag(tagName string) bool {
	for _, pattern := range at.PolicyValidator.Policy.Protection.ProtectedTags {
		if matched, _ := filepath.Match(pattern, tagName); matched {
			return true
		}
	}
	return false
}

// sendNotifications sends notifications for tag operations
func (at *AutoTagger) sendNotifications(operation *TagOperation, event string) error {
	var errors []error

	// Send Slack notifications
	if at.Config.Integrations.Slack.WebhookURL != "" {
		if err := at.sendSlackNotification(operation, event); err != nil {
			errors = append(errors, fmt.Errorf("slack notification failed: %w", err))
		} else {
			operation.Result.NotificationsSent = append(operation.Result.NotificationsSent, "slack")
		}
	}

	// Send email notifications
	if at.Config.Integrations.Email.SMTPHost != "" {
		if err := at.sendEmailNotification(operation, event); err != nil {
			errors = append(errors, fmt.Errorf("email notification failed: %w", err))
		} else {
			operation.Result.NotificationsSent = append(operation.Result.NotificationsSent, "email")
		}
	}

	if len(errors) > 0 {
		return fmt.Errorf("notification errors: %v", errors)
	}

	return nil
}

// sendSlackNotification sends a Slack notification
func (at *AutoTagger) sendSlackNotification(operation *TagOperation, event string) error {
	// This would implement Slack webhook notification
	fmt.Printf("Sending Slack notification for %s: %s\n", event, operation.TagName)
	return nil
}

// sendEmailNotification sends an email notification
func (at *AutoTagger) sendEmailNotification(operation *TagOperation, event string) error {
	// This would implement email notification
	fmt.Printf("Sending email notification for %s: %s\n", event, operation.TagName)
	return nil
}

// generateOperationID generates a unique operation ID
func generateOperationID() string {
	return fmt.Sprintf("tag-op-%d", time.Now().UnixNano())
}

// LoadAutoTaggerConfig loads configuration from file
func LoadAutoTaggerConfig(configPath string) (*AutoTaggerConfig, error) {
	if configPath == "" {
		return getDefaultConfig(), nil
	}

	data, err := os.ReadFile(configPath)
	if err != nil {
		if os.IsNotExist(err) {
			return getDefaultConfig(), nil
		}
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var config AutoTaggerConfig
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	// Set defaults for missing fields
	if config.TagPrefix == "" {
		config.TagPrefix = "v"
	}
	if config.VersionStrategy == "" {
		config.VersionStrategy = "auto"
	}
	if len(config.RequiredBranches) == 0 {
		config.RequiredBranches = []string{"main", "master"}
	}

	return &config, nil
}

// getDefaultConfig returns a default configuration
func getDefaultConfig() *AutoTaggerConfig {
	return &AutoTaggerConfig{
		RepoPath:            ".",
		DryRun:              false,
		ChangelogPath:       "CHANGELOG.md",
		PolicyPath:          ".tag-policy.json",
		AutoPush:            false,
		CreateGitHubRelease: false,
		SignTags:            false,
		RequiredBranches:    []string{"main", "master"},
		AllowDirtyWorkTree:  false,
		TagPrefix:           "v",
		VersionStrategy:     "auto",
		NotificationChannels: []string{},
		Environment:         make(map[string]string),
		Integrations: IntegrationConfig{
			GitHub: GitHubConfig{
				AutoRelease:     true,
				UploadArtifacts: true,
				GenerateNotes:   true,
				MarkAsLatest:    true,
			},
		},
	}
}

// SaveConfig saves the configuration to file
func (at *AutoTagger) SaveConfig() error {
	if at.Config.ConfigPath == "" {
		return fmt.Errorf("no config path specified")
	}

	data, err := json.MarshalIndent(at.Config, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}

	// Ensure directory exists
	dir := filepath.Dir(at.Config.ConfigPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}

	if err := os.WriteFile(at.Config.ConfigPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}

	return nil
}

// Cleanup performs cleanup operations
func (at *AutoTagger) Cleanup() error {
	// This would perform any necessary cleanup
	return nil
}