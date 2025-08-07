package tagging

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

// GitTagger handles Git tagging operations
type GitTagger struct {
	RepoPath string
	DryRun   bool
}

// TagInfo contains information about a Git tag
type TagInfo struct {
	Name        string
	Hash        string
	Date        time.Time
	Message     string
	Annotated   bool
	Author      string
	AuthorEmail string
}

// NewGitTagger creates a new GitTagger instance
func NewGitTagger(repoPath string, dryRun bool) *GitTagger {
	return &GitTagger{
		RepoPath: repoPath,
		DryRun:   dryRun,
	}
}

// GetLatestTag retrieves the latest Git tag
func (gt *GitTagger) GetLatestTag() (*TagInfo, error) {
	cmd := exec.Command("git", "describe", "--tags", "--abbrev=0")
	cmd.Dir = gt.RepoPath
	
	output, err := cmd.Output()
	if err != nil {
		// No tags found
		return nil, nil
	}

	tagName := strings.TrimSpace(string(output))
	return gt.GetTagInfo(tagName)
}

// GetTagInfo retrieves detailed information about a specific tag
func (gt *GitTagger) GetTagInfo(tagName string) (*TagInfo, error) {
	// Get tag details
	cmd := exec.Command("git", "show", "--format=%H|%at|%an|%ae|%s", "--no-patch", tagName)
	cmd.Dir = gt.RepoPath
	
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to get tag info: %w", err)
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	if len(lines) == 0 {
		return nil, fmt.Errorf("invalid tag output")
	}

	parts := strings.Split(lines[0], "|")
	if len(parts) < 5 {
		return nil, fmt.Errorf("invalid tag format")
	}

	// Parse timestamp
	timestamp := parts[1]
	var date time.Time
	if timestamp != "" {
		if ts, err := time.Parse("1136239445", timestamp); err == nil {
			date = ts
		}
	}

	return &TagInfo{
		Name:        tagName,
		Hash:        parts[0],
		Date:        date,
		Author:      parts[2],
		AuthorEmail: parts[3],
		Message:     strings.Join(parts[4:], "|"),
		Annotated:   gt.isAnnotatedTag(tagName),
	}, nil
}

// isAnnotatedTag checks if a tag is annotated
func (gt *GitTagger) isAnnotatedTag(tagName string) bool {
	cmd := exec.Command("git", "cat-file", "-t", tagName)
	cmd.Dir = gt.RepoPath
	
	output, err := cmd.Output()
	if err != nil {
		return false
	}
	
	return strings.TrimSpace(string(output)) == "tag"
}

// GetCommitsSinceTag retrieves commits since the specified tag
func (gt *GitTagger) GetCommitsSinceTag(tagName string) ([]string, error) {
	var cmd *exec.Cmd
	if tagName == "" {
		// Get all commits if no tag
		cmd = exec.Command("git", "log", "--pretty=format:%s", "HEAD")
	} else {
		// Get commits since tag
		cmd = exec.Command("git", "log", "--pretty=format:%s", fmt.Sprintf("%s..HEAD", tagName))
	}
	
	cmd.Dir = gt.RepoPath
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to get commits: %w", err)
	}

	if strings.TrimSpace(string(output)) == "" {
		return []string{}, nil
	}

	commits := strings.Split(strings.TrimSpace(string(output)), "\n")
	return commits, nil
}

// CreateTag creates a new Git tag
func (gt *GitTagger) CreateTag(tagName, message string, annotated bool) error {
	if gt.DryRun {
		fmt.Printf("[DRY RUN] Would create tag: %s with message: %s\n", tagName, message)
		return nil
	}

	var cmd *exec.Cmd
	if annotated {
		cmd = exec.Command("git", "tag", "-a", tagName, "-m", message)
	} else {
		cmd = exec.Command("git", "tag", tagName)
	}
	
	cmd.Dir = gt.RepoPath
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to create tag: %w", err)
	}

	return nil
}

// TagExists checks if a tag already exists
func (gt *GitTagger) TagExists(tagName string) bool {
	cmd := exec.Command("git", "tag", "-l", tagName)
	cmd.Dir = gt.RepoPath
	
	output, err := cmd.Output()
	if err != nil {
		return false
	}
	
	return strings.TrimSpace(string(output)) == tagName
}

// DeleteTag deletes a Git tag
func (gt *GitTagger) DeleteTag(tagName string) error {
	if gt.DryRun {
		fmt.Printf("[DRY RUN] Would delete tag: %s\n", tagName)
		return nil
	}

	cmd := exec.Command("git", "tag", "-d", tagName)
	cmd.Dir = gt.RepoPath
	
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to delete tag: %w", err)
	}

	return nil
}

// PushTag pushes a tag to the remote repository
func (gt *GitTagger) PushTag(tagName string) error {
	if gt.DryRun {
		fmt.Printf("[DRY RUN] Would push tag: %s\n", tagName)
		return nil
	}

	cmd := exec.Command("git", "push", "origin", tagName)
	cmd.Dir = gt.RepoPath
	
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to push tag: %w", err)
	}

	return nil
}

// GetAllTags retrieves all Git tags sorted by version
func (gt *GitTagger) GetAllTags() ([]*TagInfo, error) {
	cmd := exec.Command("git", "tag", "-l", "--sort=-version:refname")
	cmd.Dir = gt.RepoPath
	
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to get tags: %w", err)
	}

	if strings.TrimSpace(string(output)) == "" {
		return []*TagInfo{}, nil
	}

	tagNames := strings.Split(strings.TrimSpace(string(output)), "\n")
	var tags []*TagInfo

	for _, tagName := range tagNames {
		tagInfo, err := gt.GetTagInfo(tagName)
		if err != nil {
			continue // Skip invalid tags
		}
		tags = append(tags, tagInfo)
	}

	return tags, nil
}

// ValidateTagName validates a tag name according to Git rules
func (gt *GitTagger) ValidateTagName(tagName string) error {
	if tagName == "" {
		return fmt.Errorf("tag name cannot be empty")
	}

	// Git tag name restrictions
	invalidPatterns := []string{
		`\.\.`,           // No double dots
		`^\.`,            // Cannot start with dot
		`\.$`,            // Cannot end with dot
		`^-`,             // Cannot start with dash
		`\s`,             // No whitespace
		`[\x00-\x1f\x7f]`, // No control characters
		`[~^:?*\[]`,      // No special Git characters
		`@{`,             // No @{ sequence
		`\\`,             // No backslashes
	}

	for _, pattern := range invalidPatterns {
		if matched, _ := regexp.MatchString(pattern, tagName); matched {
			return fmt.Errorf("invalid tag name: %s", tagName)
		}
	}

	return nil
}

// AutoTag automatically creates a tag based on semantic versioning
func (gt *GitTagger) AutoTag(forceVersion string) (*TagInfo, error) {
	// Get latest tag
	latestTag, err := gt.GetLatestTag()
	if err != nil {
		return nil, fmt.Errorf("failed to get latest tag: %w", err)
	}

	var currentVersion string
	if latestTag != nil {
		currentVersion = latestTag.Name
	} else {
		currentVersion = "v0.0.0"
	}

	// Get commits since last tag
	var commits []string
	if latestTag != nil {
		commits, err = gt.GetCommitsSinceTag(latestTag.Name)
	} else {
		commits, err = gt.GetCommitsSinceTag("")
	}
	
	if err != nil {
		return nil, fmt.Errorf("failed to get commits: %w", err)
	}

	if len(commits) == 0 && forceVersion == "" {
		return nil, fmt.Errorf("no new commits since last tag")
	}

	// Calculate next version
	var nextVersion *SemanticVersion
	if forceVersion != "" {
		nextVersion, err = ParseVersion(forceVersion)
		if err != nil {
			return nil, fmt.Errorf("invalid force version: %w", err)
		}
	} else {
		nextVersion, err = CalculateNextVersion(currentVersion, commits)
		if err != nil {
			return nil, fmt.Errorf("failed to calculate next version: %w", err)
		}
	}

	tagName := nextVersion.String()
	
	// Validate tag name
	if err := gt.ValidateTagName(tagName); err != nil {
		return nil, err
	}

	// Check if tag already exists
	if gt.TagExists(tagName) {
		return nil, fmt.Errorf("tag %s already exists", tagName)
	}

	// Create tag message
	message := fmt.Sprintf("Release %s\n\nChanges since %s:\n", tagName, currentVersion)
	for _, commit := range commits {
		message += fmt.Sprintf("- %s\n", commit)
	}

	// Create the tag
	if err := gt.CreateTag(tagName, message, true); err != nil {
		return nil, err
	}

	return gt.GetTagInfo(tagName)
}

// HasUncommittedChanges checks if there are uncommitted changes
func (gt *GitTagger) HasUncommittedChanges() (bool, error) {
	cmd := exec.Command("git", "status", "--porcelain")
	cmd.Dir = gt.RepoPath
	
	output, err := cmd.Output()
	if err != nil {
		return false, fmt.Errorf("failed to check git status: %w", err)
	}

	return strings.TrimSpace(string(output)) != "", nil
}

// GetCurrentBranch returns the current Git branch
func (gt *GitTagger) GetCurrentBranch() (string, error) {
	cmd := exec.Command("git", "branch", "--show-current")
	cmd.Dir = gt.RepoPath
	
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get current branch: %w", err)
	}

	return strings.TrimSpace(string(output)), nil
}

// Interactive prompts user for confirmation
func (gt *GitTagger) Interactive(message string) bool {
	if gt.DryRun {
		fmt.Printf("[DRY RUN] %s (y/N): y\n", message)
		return true
	}

	fmt.Printf("%s (y/N): ", message)
	reader := bufio.NewReader(os.Stdin)
	response, err := reader.ReadString('\n')
	if err != nil {
		return false
	}

	response = strings.ToLower(strings.TrimSpace(response))
	return response == "y" || response == "yes"
}