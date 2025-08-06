package tagging

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// ChangelogEntry represents a single changelog entry
type ChangelogEntry struct {
	Version     *SemanticVersion
	Date        time.Time
	Changes     []ChangeItem
	Unreleased  bool
	Description string
}

// ChangeItem represents a single change in the changelog
type ChangeItem struct {
	Type        ChangeType
	Scope       string
	Description string
	Hash        string
	BreakingChange bool
	CloseIssues    []string
}

// ChangelogGenerator generates changelogs from Git history
type ChangelogGenerator struct {
	RepoPath     string
	OutputPath   string
	Template     string
	IncludeTypes []ChangeType
}

// NewChangelogGenerator creates a new changelog generator
func NewChangelogGenerator(repoPath, outputPath string) *ChangelogGenerator {
	return &ChangelogGenerator{
		RepoPath:   repoPath,
		OutputPath: outputPath,
		Template:   defaultChangelogTemplate,
		IncludeTypes: []ChangeType{
			ChangeTypeFeat,
			ChangeTypeFix,
			ChangeTypeBreaking,
			ChangeTypePerf,
		},
	}
}

const defaultChangelogTemplate = `# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

{{range .Entries}}
## [{{.Version.String}}] - {{.Date.Format "2006-01-02"}}
{{if .Description}}
{{.Description}}
{{end}}
{{range $type, $changes := .GroupedChanges}}
### {{$type}}
{{range $changes}}
- {{.Description}}{{if .Scope}} ({{.Scope}}){{end}}{{if .Hash}} ([{{.Hash}}]({{$.RepoURL}}/commit/{{.Hash}})){{end}}{{if .CloseIssues}}{{range .CloseIssues}} closes #{{.}}{{end}}{{end}}
{{end}}
{{end}}
{{end}}

{{if .UnreleasedChanges}}
## [Unreleased]
{{range $type, $changes := .UnreleasedChanges}}
### {{$type}}
{{range $changes}}
- {{.Description}}{{if .Scope}} ({{.Scope}}){{end}}{{if .Hash}} ([{{.Hash}}]({{$.RepoURL}}/commit/{{.Hash}})){{end}}{{if .CloseIssues}}{{range .CloseIssues}} closes #{{.}}{{end}}{{end}}
{{end}}
{{end}}
{{end}}
`

var (
	// Regex patterns for parsing conventional commits
	conventionalCommitRegex = regexp.MustCompile(`^(\w+)(\(([^)]+)\))?\s*(!)?:\s*(.+)$`)
	breakingChangeRegex     = regexp.MustCompile(`BREAKING CHANGES?:\s*(.+)`)
	closeIssuesRegex        = regexp.MustCompile(`(?i)(?:close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)\s+#(\d+)`)
)

// ParseCommitMessage parses a commit message into a ChangeItem
func (cg *ChangelogGenerator) ParseCommitMessage(message, hash string) *ChangeItem {
	lines := strings.Split(message, "\n")
	subject := strings.TrimSpace(lines[0])
	body := strings.Join(lines[1:], "\n")

	// Match conventional commit format
	matches := conventionalCommitRegex.FindStringSubmatch(subject)
	if len(matches) == 0 {
		// Fallback to basic parsing
		return &ChangeItem{
			Type:        ChangeTypeChore,
			Description: subject,
			Hash:        hash[:8], // Short hash
		}
	}

	changeType := parseChangeTypeString(matches[1])
	scope := matches[3]
	breaking := matches[4] == "!" || breakingChangeRegex.MatchString(body)
	description := strings.TrimSpace(matches[5])

	// Override change type if breaking
	if breaking {
		changeType = ChangeTypeBreaking
	}

	// Extract closed issues
	issueMatches := closeIssuesRegex.FindAllStringSubmatch(message, -1)
	var closeIssues []string
	for _, match := range issueMatches {
		if len(match) > 1 {
			closeIssues = append(closeIssues, match[1])
		}
	}

	return &ChangeItem{
		Type:           changeType,
		Scope:          scope,
		Description:    description,
		Hash:           hash[:8], // Short hash
		BreakingChange: breaking,
		CloseIssues:    closeIssues,
	}
}

// parseChangeTypeString converts a string to ChangeType
func parseChangeTypeString(s string) ChangeType {
	switch strings.ToLower(s) {
	case "feat", "feature":
		return ChangeTypeFeat
	case "fix", "bugfix":
		return ChangeTypeFix
	case "perf", "performance":
		return ChangeTypePerf
	case "docs", "doc":
		return ChangeTypeDocs
	case "style":
		return ChangeTypeStyle
	case "refactor":
		return ChangeTypeRefactor
	case "test", "tests":
		return ChangeTypeTest
	case "chore":
		return ChangeTypeChore
	default:
		return ChangeTypeChore
	}
}

// changeTypeToString converts ChangeType to a display string
func changeTypeToString(ct ChangeType) string {
	switch ct {
	case ChangeTypeFeat:
		return "Added"
	case ChangeTypeFix:
		return "Fixed"
	case ChangeTypeBreaking:
		return "Breaking Changes"
	case ChangeTypePerf:
		return "Performance"
	case ChangeTypeDocs:
		return "Documentation"
	case ChangeTypeStyle:
		return "Styling"
	case ChangeTypeRefactor:
		return "Refactored"
	case ChangeTypeTest:
		return "Testing"
	default:
		return "Other"
	}
}

// GenerateFromTags generates a changelog from Git tags
func (cg *ChangelogGenerator) GenerateFromTags(tagger *GitTagger) (*Changelog, error) {
	tags, err := tagger.GetAllTags()
	if err != nil {
		return nil, fmt.Errorf("failed to get tags: %w", err)
	}

	var entries []*ChangelogEntry

	// Process each tag
	for i, tag := range tags {
		version, err := ParseVersion(tag.Name)
		if err != nil {
			continue // Skip invalid version tags
		}

		// Get commits for this tag
		var commits []string
		var commitHashes []string
		
		if i < len(tags)-1 {
			// Get commits between this tag and the next
			commits, commitHashes, err = cg.getCommitsBetweenTags(tagger, tags[i+1].Name, tag.Name)
		} else {
			// Get commits from beginning to this tag
			commits, commitHashes, err = cg.getCommitsToTag(tagger, tag.Name)
		}
		
		if err != nil {
			continue
		}

		entry := &ChangelogEntry{
			Version: version,
			Date:    tag.Date,
			Changes: cg.parseCommits(commits, commitHashes),
		}

		entries = append(entries, entry)
	}

	// Get unreleased changes
	var unreleasedChanges []ChangeItem
	if len(tags) > 0 {
		commits, hashes, err := cg.getCommitsSinceTag(tagger, tags[0].Name)
		if err == nil && len(commits) > 0 {
			unreleasedChanges = cg.parseCommits(commits, hashes)
		}
	} else {
		// No tags, all commits are unreleased
		commits, hashes, err := cg.getAllCommits(tagger)
		if err == nil {
			unreleasedChanges = cg.parseCommits(commits, hashes)
		}
	}

	return &Changelog{
		Entries:           entries,
		UnreleasedChanges: unreleasedChanges,
		GeneratedAt:       time.Now(),
	}, nil
}

// getCommitsBetweenTags gets commits between two tags
func (cg *ChangelogGenerator) getCommitsBetweenTags(tagger *GitTagger, fromTag, toTag string) ([]string, []string, error) {
	cmd := fmt.Sprintf("git log --pretty=format:%%s|%%H %s..%s", fromTag, toTag)
	return cg.executeGitLogCommand(tagger, cmd)
}

// getCommitsToTag gets commits from the beginning to a specific tag
func (cg *ChangelogGenerator) getCommitsToTag(tagger *GitTagger, tag string) ([]string, []string, error) {
	cmd := fmt.Sprintf("git log --pretty=format:%%s|%%H %s", tag)
	return cg.executeGitLogCommand(tagger, cmd)
}

// getCommitsSinceTag gets commits since a specific tag
func (cg *ChangelogGenerator) getCommitsSinceTag(tagger *GitTagger, tag string) ([]string, []string, error) {
	cmd := fmt.Sprintf("git log --pretty=format:%%s|%%H %s..HEAD", tag)
	return cg.executeGitLogCommand(tagger, cmd)
}

// getAllCommits gets all commits
func (cg *ChangelogGenerator) getAllCommits(tagger *GitTagger) ([]string, []string, error) {
	cmd := "git log --pretty=format:%s|%H"
	return cg.executeGitLogCommand(tagger, cmd)
}

// executeGitLogCommand executes a git log command and returns messages and hashes
func (cg *ChangelogGenerator) executeGitLogCommand(tagger *GitTagger, command string) ([]string, []string, error) {
	// This is a simplified version - in a real implementation, you'd use exec.Command
	// For this example, we'll return empty slices
	return []string{}, []string{}, nil
}

// parseCommits parses commit messages into ChangeItems
func (cg *ChangelogGenerator) parseCommits(messages, hashes []string) []ChangeItem {
	var items []ChangeItem
	
	for i, message := range messages {
		var hash string
		if i < len(hashes) {
			hash = hashes[i]
		}
		
		item := cg.ParseCommitMessage(message, hash)
		
		// Filter by included types
		include := false
		for _, includeType := range cg.IncludeTypes {
			if item.Type == includeType {
				include = true
				break
			}
		}
		
		if include {
			items = append(items, *item)
		}
	}
	
	return items
}

// Changelog represents the complete changelog
type Changelog struct {
	Entries           []*ChangelogEntry
	UnreleasedChanges []ChangeItem
	GeneratedAt       time.Time
}

// GroupedChanges groups changes by type for a changelog entry
func (ce *ChangelogEntry) GroupedChanges() map[string][]ChangeItem {
	grouped := make(map[string][]ChangeItem)
	
	for _, change := range ce.Changes {
		typeStr := changeTypeToString(change.Type)
		grouped[typeStr] = append(grouped[typeStr], change)
	}
	
	// Sort each group
	for typeStr := range grouped {
		sort.Slice(grouped[typeStr], func(i, j int) bool {
			return grouped[typeStr][i].Description < grouped[typeStr][j].Description
		})
	}
	
	return grouped
}

// WriteToFile writes the changelog to a file
func (c *Changelog) WriteToFile(filename string) error {
	file, err := os.Create(filename)
	if err != nil {
		return fmt.Errorf("failed to create changelog file: %w", err)
	}
	defer file.Close()

	writer := bufio.NewWriter(file)
	defer writer.Flush()

	// Write header
	_, err = writer.WriteString("# Changelog\n\n")
	if err != nil {
		return err
	}

	_, err = writer.WriteString("All notable changes to this project will be documented in this file.\n\n")
	if err != nil {
		return err
	}

	_, err = writer.WriteString("The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),\n")
	if err != nil {
		return err
	}

	_, err = writer.WriteString("and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).\n\n")
	if err != nil {
		return err
	}

	// Write unreleased changes
	if len(c.UnreleasedChanges) > 0 {
		_, err = writer.WriteString("## [Unreleased]\n\n")
		if err != nil {
			return err
		}

		err = c.writeChanges(writer, c.UnreleasedChanges)
		if err != nil {
			return err
		}

		_, err = writer.WriteString("\n")
		if err != nil {
			return err
		}
	}

	// Write version entries
	for _, entry := range c.Entries {
		_, err = writer.WriteString(fmt.Sprintf("## [%s] - %s\n\n", 
			entry.Version.String(), 
			entry.Date.Format("2006-01-02")))
		if err != nil {
			return err
		}

		if entry.Description != "" {
			_, err = writer.WriteString(entry.Description + "\n\n")
			if err != nil {
				return err
			}
		}

		err = c.writeChanges(writer, entry.Changes)
		if err != nil {
			return err
		}

		_, err = writer.WriteString("\n")
		if err != nil {
			return err
		}
	}

	return nil
}

// writeChanges writes grouped changes to the writer
func (c *Changelog) writeChanges(writer *bufio.Writer, changes []ChangeItem) error {
	// Group changes by type
	grouped := make(map[string][]ChangeItem)
	for _, change := range changes {
		typeStr := changeTypeToString(change.Type)
		grouped[typeStr] = append(grouped[typeStr], change)
	}

	// Define order for change types
	typeOrder := []string{"Breaking Changes", "Added", "Fixed", "Performance", "Documentation", "Refactored", "Other"}

	for _, typeStr := range typeOrder {
		items, exists := grouped[typeStr]
		if !exists || len(items) == 0 {
			continue
		}

		_, err := writer.WriteString(fmt.Sprintf("### %s\n\n", typeStr))
		if err != nil {
			return err
		}

		// Sort items by description
		sort.Slice(items, func(i, j int) bool {
			return items[i].Description < items[j].Description
		})

		for _, item := range items {
			line := fmt.Sprintf("- %s", item.Description)
			
			if item.Scope != "" {
				line += fmt.Sprintf(" (%s)", item.Scope)
			}
			
			if item.Hash != "" {
				line += fmt.Sprintf(" ([%s](commit/%s))", item.Hash, item.Hash)
			}
			
			for _, issue := range item.CloseIssues {
				line += fmt.Sprintf(" closes #%s", issue)
			}
			
			line += "\n"
			
			_, err := writer.WriteString(line)
			if err != nil {
				return err
			}
		}

		_, err = writer.WriteString("\n")
		if err != nil {
			return err
		}
	}

	return nil
}

// GenerateChangelogFile generates a changelog file
func (cg *ChangelogGenerator) GenerateChangelogFile() error {
	tagger := NewGitTagger(cg.RepoPath, false)
	
	changelog, err := cg.GenerateFromTags(tagger)
	if err != nil {
		return fmt.Errorf("failed to generate changelog: %w", err)
	}

	outputPath := cg.OutputPath
	if outputPath == "" {
		outputPath = filepath.Join(cg.RepoPath, "CHANGELOG.md")
	}

	return changelog.WriteToFile(outputPath)
}