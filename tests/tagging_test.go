package tagging

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestSemanticVersion(t *testing.T) {
	tests := []struct {
		name        string
		version     string
		expected    *SemanticVersion
		expectError bool
	}{
		{
			name:    "valid semver",
			version: "v1.2.3",
			expected: &SemanticVersion{
				Major: 1, Minor: 2, Patch: 3,
			},
			expectError: false,
		},
		{
			name:    "semver with prerelease",
			version: "v1.2.3-alpha.1",
			expected: &SemanticVersion{
				Major: 1, Minor: 2, Patch: 3, PreRelease: "alpha.1",
			},
			expectError: false,
		},
		{
			name:        "invalid format",
			version:     "invalid",
			expected:    nil,
			expectError: true,
		},
		{
			name:    "empty version",
			version: "",
			expected: &SemanticVersion{
				Major: 0, Minor: 0, Patch: 0,
			},
			expectError: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := ParseVersion(tt.version)
			
			if tt.expectError {
				if err == nil {
					t.Errorf("expected error but got none")
				}
				return
			}
			
			if err != nil {
				t.Errorf("unexpected error: %v", err)
				return
			}
			
			if result.Major != tt.expected.Major ||
				result.Minor != tt.expected.Minor ||
				result.Patch != tt.expected.Patch ||
				result.PreRelease != tt.expected.PreRelease {
				t.Errorf("expected %+v, got %+v", tt.expected, result)
			}
		})
	}
}

func TestVersionBump(t *testing.T) {
	baseVersion := &SemanticVersion{Major: 1, Minor: 2, Patch: 3}

	tests := []struct {
		name        string
		versionType VersionType
		expected    *SemanticVersion
	}{
		{
			name:        "patch bump",
			versionType: PatchVersion,
			expected:    &SemanticVersion{Major: 1, Minor: 2, Patch: 4},
		},
		{
			name:        "minor bump",
			versionType: MinorVersion,
			expected:    &SemanticVersion{Major: 1, Minor: 3, Patch: 0},
		},
		{
			name:        "major bump",
			versionType: MajorVersion,
			expected:    &SemanticVersion{Major: 2, Minor: 0, Patch: 0},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := baseVersion.Bump(tt.versionType)
			
			if result.Major != tt.expected.Major ||
				result.Minor != tt.expected.Minor ||
				result.Patch != tt.expected.Patch {
				t.Errorf("expected %+v, got %+v", tt.expected, result)
			}
		})
	}
}

func TestAnalyzeCommitMessage(t *testing.T) {
	tests := []struct {
		name     string
		message  string
		expected ChangeType
	}{
		{
			name:     "feat commit",
			message:  "feat: add new feature",
			expected: ChangeTypeFeat,
		},
		{
			name:     "fix commit",
			message:  "fix: resolve bug",
			expected: ChangeTypeFix,
		},
		{
			name:     "breaking change",
			message:  "feat!: breaking change",
			expected: ChangeTypeBreaking,
		},
		{
			name:     "docs commit",
			message:  "docs: update readme",
			expected: ChangeTypeDocs,
		},
		{
			name:     "non-conventional commit",
			message:  "update some code",
			expected: ChangeTypeChore,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := AnalyzeCommitMessage(tt.message)
			
			if result != tt.expected {
				t.Errorf("expected %v, got %v", tt.expected, result)
			}
		})
	}
}

func TestDetermineVersionBump(t *testing.T) {
	tests := []struct {
		name     string
		commits  []string
		expected VersionType
	}{
		{
			name: "breaking change",
			commits: []string{
				"feat!: breaking change",
				"fix: some bug",
			},
			expected: MajorVersion,
		},
		{
			name: "new feature",
			commits: []string{
				"feat: new feature",
				"fix: some bug",
			},
			expected: MinorVersion,
		},
		{
			name: "bug fixes only",
			commits: []string{
				"fix: bug 1",
				"fix: bug 2",
			},
			expected: PatchVersion,
		},
		{
			name: "chores only",
			commits: []string{
				"chore: update dependencies",
				"docs: update readme",
			},
			expected: PatchVersion,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := DetermineVersionBump(tt.commits)
			
			if result != tt.expected {
				t.Errorf("expected %v, got %v", tt.expected, result)
			}
		})
	}
}

func TestGitTaggerValidation(t *testing.T) {
	tagger := NewGitTagger("/tmp", true)

	tests := []struct {
		name        string
		tagName     string
		expectError bool
	}{
		{
			name:        "valid tag",
			tagName:     "v1.0.0",
			expectError: false,
		},
		{
			name:        "empty tag",
			tagName:     "",
			expectError: true,
		},
		{
			name:        "tag with spaces",
			tagName:     "v1.0.0 invalid",
			expectError: true,
		},
		{
			name:        "tag starting with dot",
			tagName:     ".v1.0.0",
			expectError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tagger.ValidateTagName(tt.tagName)
			
			if tt.expectError && err == nil {
				t.Errorf("expected error but got none")
			}
			
			if !tt.expectError && err != nil {
				t.Errorf("unexpected error: %v", err)
			}
		})
	}
}

func TestPolicyValidator(t *testing.T) {
	// Create a temporary directory for testing
	tmpDir, err := os.MkdirTemp("", "policy-test")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	// Create a test policy validator
	validator, err := NewPolicyValidator("")
	if err != nil {
		t.Fatal(err)
	}

	tests := []struct {
		name        string
		tagName     string
		branch      string
		expectValid bool
	}{
		{
			name:        "valid semver tag on main",
			tagName:     "v1.0.0",
			branch:      "main",
			expectValid: true,
		},
		{
			name:        "invalid format",
			tagName:     "invalid-tag",
			branch:      "main",
			expectValid: false,
		},
		{
			name:        "valid tag on feature branch",
			tagName:     "v1.0.0",
			branch:      "feature/test",
			expectValid: false, // Should warn about branch
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tagger := NewGitTagger(tmpDir, true)
			result := validator.ValidateTag(tt.tagName, tt.branch, "", tagger)
			
			if tt.expectValid && !result.Valid {
				t.Errorf("expected valid result but got %d violations", len(result.Violations))
			}
			
			if !tt.expectValid && result.Valid && len(result.Warnings) == 0 {
				t.Errorf("expected invalid result but validation passed")
			}
		})
	}
}

func TestChangelogGeneration(t *testing.T) {
	// Create a temporary directory for testing
	tmpDir, err := os.MkdirTemp("", "changelog-test")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	generator := NewChangelogGenerator(tmpDir, filepath.Join(tmpDir, "CHANGELOG.md"))

	// Test commit message parsing
	tests := []struct {
		name     string
		message  string
		hash     string
		expected *ChangeItem
	}{
		{
			name:    "feat commit",
			message: "feat(auth): add login functionality",
			hash:    "abc123456789",
			expected: &ChangeItem{
				Type:        ChangeTypeFeat,
				Scope:       "auth",
				Description: "add login functionality",
				Hash:        "abc12345",
			},
		},
		{
			name:    "fix with issue",
			message: "fix: resolve memory leak closes #123",
			hash:    "def123456789",
			expected: &ChangeItem{
				Type:        ChangeTypeFix,
				Description: "resolve memory leak",
				Hash:        "def12345",
				CloseIssues: []string{"123"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := generator.ParseCommitMessage(tt.message, tt.hash)
			
			if result.Type != tt.expected.Type {
				t.Errorf("expected type %v, got %v", tt.expected.Type, result.Type)
			}
			
			if result.Scope != tt.expected.Scope {
				t.Errorf("expected scope %s, got %s", tt.expected.Scope, result.Scope)
			}
			
			if result.Description != tt.expected.Description {
				t.Errorf("expected description %s, got %s", tt.expected.Description, result.Description)
			}
		})
	}
}

func TestAutoTaggerConfig(t *testing.T) {
	// Test default config
	config := getDefaultConfig()
	
	if config.TagPrefix != "v" {
		t.Errorf("expected default tag prefix 'v', got %s", config.TagPrefix)
	}
	
	if config.VersionStrategy != "auto" {
		t.Errorf("expected default version strategy 'auto', got %s", config.VersionStrategy)
	}
	
	if len(config.RequiredBranches) == 0 {
		t.Errorf("expected default required branches, got empty list")
	}
}

func TestReleaseArtifacts(t *testing.T) {
	// Create a temporary directory for testing
	tmpDir, err := os.MkdirTemp("", "artifacts-test")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	config := &ReleaseConfig{
		RepoPath: tmpDir,
		DryRun:   true,
	}

	automation := NewReleaseAutomation(config)
	
	context := &ReleaseContext{
		NextVersion: &SemanticVersion{Major: 1, Minor: 0, Patch: 0},
	}

	err = automation.CreateReleaseArtifacts(context)
	if err != nil {
		t.Errorf("unexpected error creating artifacts: %v", err)
	}

	if len(context.Artifacts) == 0 {
		t.Errorf("expected artifacts to be created")
	}
}

func TestGitHubIntegration(t *testing.T) {
	// Skip if no GitHub token available
	if os.Getenv("GITHUB_TOKEN") == "" {
		t.Skip("GITHUB_TOKEN not set, skipping GitHub integration tests")
	}

	integration := NewGitHubIntegration(".")
	
	err := integration.ValidateToken()
	if err != nil {
		t.Errorf("GitHub token validation failed: %v", err)
	}
}

// Benchmark tests
func BenchmarkParseVersion(b *testing.B) {
	for i := 0; i < b.N; i++ {
		_, _ = ParseVersion("v1.2.3-alpha.1+build.123")
	}
}

func BenchmarkAnalyzeCommitMessage(b *testing.B) {
	message := "feat(api): add new endpoint for user management"
	for i := 0; i < b.N; i++ {
		_ = AnalyzeCommitMessage(message)
	}
}

func BenchmarkPolicyValidation(b *testing.B) {
	validator, _ := NewPolicyValidator("")
	tagger := NewGitTagger("/tmp", true)
	
	for i := 0; i < b.N; i++ {
		_ = validator.ValidateTag("v1.0.0", "main", "", tagger)
	}
}

// Helper functions for testing
func createTempRepo(t *testing.T) string {
	tmpDir, err := os.MkdirTemp("", "git-test")
	if err != nil {
		t.Fatal(err)
	}
	return tmpDir
}

func createTestConfig(repoPath string) *AutoTaggerConfig {
	return &AutoTaggerConfig{
		RepoPath:            repoPath,
		DryRun:              true,
		ChangelogPath:       filepath.Join(repoPath, "CHANGELOG.md"),
		PolicyPath:          filepath.Join(repoPath, ".tag-policy.json"),
		AutoPush:            false,
		CreateGitHubRelease: false,
		RequiredBranches:    []string{"main"},
		TagPrefix:           "v",
		VersionStrategy:     "auto",
	}
}

// Integration test
func TestFullReleaseWorkflow(t *testing.T) {
	// Skip integration test in short mode
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	tmpDir := createTempRepo(t)
	defer os.RemoveAll(tmpDir)

	config := createTestConfig(tmpDir)
	autoTagger, err := NewAutoTaggerWithConfig(config)
	if err != nil {
		t.Fatal(err)
	}

	// Test status
	status, err := autoTagger.GetStatus()
	if err != nil {
		t.Errorf("failed to get status: %v", err)
	}

	if status["repository"] != tmpDir {
		t.Errorf("expected repository %s, got %s", tmpDir, status["repository"])
	}

	// Test changelog generation (should not fail even without git repo)
	err = autoTagger.GenerateChangelog()
	if err == nil {
		// Check if changelog was created
		changelogPath := filepath.Join(tmpDir, "CHANGELOG.md")
		if _, err := os.Stat(changelogPath); err != nil && !os.IsNotExist(err) {
			t.Errorf("unexpected error checking changelog: %v", err)
		}
	}
}