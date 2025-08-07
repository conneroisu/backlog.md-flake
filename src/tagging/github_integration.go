package tagging

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// GitHubIntegration handles GitHub API operations
type GitHubIntegration struct {
	RepoPath   string
	Owner      string
	Repo       string
	Token      string
	BaseURL    string
	HTTPClient *http.Client
}

// GitHubRelease represents a GitHub release
type GitHubRelease struct {
	ID            int64              `json:"id,omitempty"`
	TagName       string             `json:"tag_name"`
	Name          string             `json:"name"`
	Body          string             `json:"body"`
	Draft         bool               `json:"draft"`
	PreRelease    bool               `json:"prerelease"`
	GenerateNotes bool               `json:"generate_release_notes"`
	CreatedAt     *time.Time         `json:"created_at,omitempty"`
	PublishedAt   *time.Time         `json:"published_at,omitempty"`
	Assets        []GitHubAsset      `json:"assets,omitempty"`
	HTMLURL       string             `json:"html_url,omitempty"`
	UploadURL     string             `json:"upload_url,omitempty"`
}

// GitHubAsset represents a release asset
type GitHubAsset struct {
	ID                 int64     `json:"id,omitempty"`
	Name               string    `json:"name"`
	Label              string    `json:"label,omitempty"`
	ContentType        string    `json:"content_type"`
	Size               int64     `json:"size,omitempty"`
	DownloadCount      int       `json:"download_count,omitempty"`
	CreatedAt          *time.Time `json:"created_at,omitempty"`
	UpdatedAt          *time.Time `json:"updated_at,omitempty"`
	BrowserDownloadURL string    `json:"browser_download_url,omitempty"`
}

// GitHubRepository represents repository information
type GitHubRepository struct {
	ID       int64  `json:"id"`
	Name     string `json:"name"`
	FullName string `json:"full_name"`
	Private  bool   `json:"private"`
	HTMLURL  string `json:"html_url"`
	CloneURL string `json:"clone_url"`
	SSHURL   string `json:"ssh_url"`
}

// NewGitHubIntegration creates a new GitHub integration
func NewGitHubIntegration(repoPath string) *GitHubIntegration {
	return &GitHubIntegration{
		RepoPath:   repoPath,
		BaseURL:    "https://api.github.com",
		HTTPClient: &http.Client{Timeout: 30 * time.Second},
		Token:      os.Getenv("GITHUB_TOKEN"),
	}
}

// Initialize sets up the GitHub integration
func (gi *GitHubIntegration) Initialize() error {
	if gi.Token == "" {
		return fmt.Errorf("GITHUB_TOKEN environment variable is required")
	}

	// Extract owner and repo from Git remote
	owner, repo, err := gi.extractRepoInfo()
	if err != nil {
		return fmt.Errorf("failed to extract repository information: %w", err)
	}

	gi.Owner = owner
	gi.Repo = repo

	return nil
}

// extractRepoInfo extracts owner and repository name from Git remote
func (gi *GitHubIntegration) extractRepoInfo() (string, string, error) {
	// This would use exec.Command to get git remote origin URL
	// For now, return placeholder values
	return "owner", "repo", nil
}

// CreateRelease creates a new GitHub release
func (gi *GitHubIntegration) CreateRelease(release *GitHubRelease) (*GitHubRelease, error) {
	if err := gi.Initialize(); err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/repos/%s/%s/releases", gi.BaseURL, gi.Owner, gi.Repo)
	
	payload, err := json.Marshal(release)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal release: %w", err)
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(payload))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "token "+gi.Token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	resp, err := gi.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to create release: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("GitHub API error (%d): %s", resp.StatusCode, string(body))
	}

	var createdRelease GitHubRelease
	if err := json.NewDecoder(resp.Body).Decode(&createdRelease); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &createdRelease, nil
}

// GetRelease retrieves a GitHub release by tag name
func (gi *GitHubIntegration) GetRelease(tagName string) (*GitHubRelease, error) {
	if err := gi.Initialize(); err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/repos/%s/%s/releases/tags/%s", gi.BaseURL, gi.Owner, gi.Repo, tagName)
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "token "+gi.Token)
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	resp, err := gi.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to get release: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("release not found: %s", tagName)
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("GitHub API error (%d): %s", resp.StatusCode, string(body))
	}

	var release GitHubRelease
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &release, nil
}

// UpdateRelease updates an existing GitHub release
func (gi *GitHubIntegration) UpdateRelease(releaseID int64, release *GitHubRelease) (*GitHubRelease, error) {
	if err := gi.Initialize(); err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/repos/%s/%s/releases/%d", gi.BaseURL, gi.Owner, gi.Repo, releaseID)
	
	payload, err := json.Marshal(release)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal release: %w", err)
	}

	req, err := http.NewRequest("PATCH", url, bytes.NewBuffer(payload))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "token "+gi.Token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	resp, err := gi.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to update release: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("GitHub API error (%d): %s", resp.StatusCode, string(body))
	}

	var updatedRelease GitHubRelease
	if err := json.NewDecoder(resp.Body).Decode(&updatedRelease); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &updatedRelease, nil
}

// DeleteRelease deletes a GitHub release
func (gi *GitHubIntegration) DeleteRelease(releaseID int64) error {
	if err := gi.Initialize(); err != nil {
		return err
	}

	url := fmt.Sprintf("%s/repos/%s/%s/releases/%d", gi.BaseURL, gi.Owner, gi.Repo, releaseID)
	
	req, err := http.NewRequest("DELETE", url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "token "+gi.Token)
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	resp, err := gi.HTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to delete release: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusNoContent {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("GitHub API error (%d): %s", resp.StatusCode, string(body))
	}

	return nil
}

// UploadAsset uploads a file as a release asset
func (gi *GitHubIntegration) UploadAsset(release *GitHubRelease, artifact ReleaseArtifact) (*GitHubAsset, error) {
	if err := gi.Initialize(); err != nil {
		return nil, err
	}

	// Check if file exists
	if _, err := os.Stat(artifact.Path); os.IsNotExist(err) {
		return nil, fmt.Errorf("asset file not found: %s", artifact.Path)
	}

	// Open file
	file, err := os.Open(artifact.Path)
	if err != nil {
		return nil, fmt.Errorf("failed to open asset file: %w", err)
	}
	defer file.Close()

	// Get file size
	fileInfo, err := file.Stat()
	if err != nil {
		return nil, fmt.Errorf("failed to get file info: %w", err)
	}

	// Prepare upload URL
	uploadURL := strings.Replace(release.UploadURL, "{?name,label}", "", -1)
	uploadURL += "?name=" + artifact.Name

	if artifact.Description != "" {
		uploadURL += "&label=" + artifact.Description
	}

	req, err := http.NewRequest("POST", uploadURL, file)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "token "+gi.Token)
	req.Header.Set("Content-Type", artifact.ContentType)
	req.Header.Set("Accept", "application/vnd.github.v3+json")
	req.ContentLength = fileInfo.Size()

	resp, err := gi.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to upload asset: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("GitHub API error (%d): %s", resp.StatusCode, string(body))
	}

	var asset GitHubAsset
	if err := json.NewDecoder(resp.Body).Decode(&asset); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &asset, nil
}

// ListReleases lists all releases for the repository
func (gi *GitHubIntegration) ListReleases(perPage, page int) ([]GitHubRelease, error) {
	if err := gi.Initialize(); err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/repos/%s/%s/releases", gi.BaseURL, gi.Owner, gi.Repo)
	
	if perPage > 0 {
		url += fmt.Sprintf("?per_page=%d", perPage)
		if page > 0 {
			url += fmt.Sprintf("&page=%d", page)
		}
	}
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "token "+gi.Token)
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	resp, err := gi.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to list releases: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("GitHub API error (%d): %s", resp.StatusCode, string(body))
	}

	var releases []GitHubRelease
	if err := json.NewDecoder(resp.Body).Decode(&releases); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return releases, nil
}

// GetRepository gets repository information
func (gi *GitHubIntegration) GetRepository() (*GitHubRepository, error) {
	if err := gi.Initialize(); err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/repos/%s/%s", gi.BaseURL, gi.Owner, gi.Repo)
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "token "+gi.Token)
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	resp, err := gi.HTTPClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to get repository: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("GitHub API error (%d): %s", resp.StatusCode, string(body))
	}

	var repo GitHubRepository
	if err := json.NewDecoder(resp.Body).Decode(&repo); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &repo, nil
}

// CreateReleaseWithAssets creates a release and uploads all specified assets
func (gi *GitHubIntegration) CreateReleaseWithAssets(release *GitHubRelease, artifacts []ReleaseArtifact) (*GitHubRelease, error) {
	// Create the release first
	createdRelease, err := gi.CreateRelease(release)
	if err != nil {
		return nil, fmt.Errorf("failed to create release: %w", err)
	}

	// Upload assets
	for _, artifact := range artifacts {
		asset, err := gi.UploadAsset(createdRelease, artifact)
		if err != nil {
			// Log error but continue with other assets
			fmt.Printf("Warning: failed to upload asset %s: %v\n", artifact.Name, err)
			continue
		}
		
		createdRelease.Assets = append(createdRelease.Assets, *asset)
	}

	return createdRelease, nil
}

// GenerateReleaseNotes generates release notes using GitHub's API
func (gi *GitHubIntegration) GenerateReleaseNotes(tagName, targetBranch, previousTagName string) (string, error) {
	if err := gi.Initialize(); err != nil {
		return "", err
	}

	url := fmt.Sprintf("%s/repos/%s/%s/releases/generate-notes", gi.BaseURL, gi.Owner, gi.Repo)
	
	payload := map[string]interface{}{
		"tag_name":         tagName,
		"target_commitish": targetBranch,
	}
	
	if previousTagName != "" {
		payload["previous_tag_name"] = previousTagName
	}

	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("failed to marshal payload: %w", err)
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(payloadBytes))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "token "+gi.Token)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	resp, err := gi.HTTPClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to generate release notes: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("GitHub API error (%d): %s", resp.StatusCode, string(body))
	}

	var result struct {
		Name string `json:"name"`
		Body string `json:"body"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("failed to decode response: %w", err)
	}

	return result.Body, nil
}

// ValidateToken validates the GitHub token
func (gi *GitHubIntegration) ValidateToken() error {
	if gi.Token == "" {
		return fmt.Errorf("GITHUB_TOKEN not set")
	}

	url := fmt.Sprintf("%s/user", gi.BaseURL)
	
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "token "+gi.Token)
	req.Header.Set("Accept", "application/vnd.github.v3+json")

	resp, err := gi.HTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to validate token: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("invalid GitHub token")
	}

	return nil
}