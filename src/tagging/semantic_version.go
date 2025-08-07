package tagging

import (
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// SemanticVersion represents a semantic version with major, minor, patch components
type SemanticVersion struct {
	Major      int
	Minor      int
	Patch      int
	PreRelease string
	BuildMeta  string
}

// VersionType represents the type of version bump required
type VersionType int

const (
	PatchVersion VersionType = iota
	MinorVersion
	MajorVersion
)

// ChangeType represents the type of change in a commit
type ChangeType int

const (
	ChangeTypeFix ChangeType = iota
	ChangeTypeFeat
	ChangeTypeBreaking
	ChangeTypeChore
	ChangeTypeDocs
	ChangeTypeStyle
	ChangeTypeRefactor
	ChangeTypePerf
	ChangeTypeTest
)

var (
	// Semantic version regex pattern
	semVerPattern = regexp.MustCompile(`^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z\-]+(?:\.[0-9A-Za-z\-]+)*))?(?:\+([0-9A-Za-z\-]+(?:\.[0-9A-Za-z\-]+)*))?$`)
	
	// Conventional commit patterns
	conventionalCommitPatterns = map[ChangeType]*regexp.Regexp{
		ChangeTypeFix:      regexp.MustCompile(`^fix(\(.+\))?\s*:\s*.+`),
		ChangeTypeFeat:     regexp.MustCompile(`^feat(\(.+\))?\s*:\s*.+`),
		ChangeTypeBreaking: regexp.MustCompile(`^.+(\(.+\))?\s*!\s*:\s*.+|^BREAKING CHANGE:`),
		ChangeTypeChore:    regexp.MustCompile(`^chore(\(.+\))?\s*:\s*.+`),
		ChangeTypeDocs:     regexp.MustCompile(`^docs(\(.+\))?\s*:\s*.+`),
		ChangeTypeStyle:    regexp.MustCompile(`^style(\(.+\))?\s*:\s*.+`),
		ChangeTypeRefactor: regexp.MustCompile(`^refactor(\(.+\))?\s*:\s*.+`),
		ChangeTypePerf:     regexp.MustCompile(`^perf(\(.+\))?\s*:\s*.+`),
		ChangeTypeTest:     regexp.MustCompile(`^test(\(.+\))?\s*:\s*.+`),
	}
)

// ParseVersion parses a semantic version string
func ParseVersion(version string) (*SemanticVersion, error) {
	if version == "" {
		return &SemanticVersion{Major: 0, Minor: 0, Patch: 0}, nil
	}

	matches := semVerPattern.FindStringSubmatch(version)
	if len(matches) == 0 {
		return nil, errors.New("invalid semantic version format")
	}

	major, err := strconv.Atoi(matches[1])
	if err != nil {
		return nil, fmt.Errorf("invalid major version: %w", err)
	}

	minor, err := strconv.Atoi(matches[2])
	if err != nil {
		return nil, fmt.Errorf("invalid minor version: %w", err)
	}

	patch, err := strconv.Atoi(matches[3])
	if err != nil {
		return nil, fmt.Errorf("invalid patch version: %w", err)
	}

	return &SemanticVersion{
		Major:      major,
		Minor:      minor,
		Patch:      patch,
		PreRelease: matches[4],
		BuildMeta:  matches[5],
	}, nil
}

// String returns the string representation of the semantic version
func (sv *SemanticVersion) String() string {
	version := fmt.Sprintf("v%d.%d.%d", sv.Major, sv.Minor, sv.Patch)
	
	if sv.PreRelease != "" {
		version += "-" + sv.PreRelease
	}
	
	if sv.BuildMeta != "" {
		version += "+" + sv.BuildMeta
	}
	
	return version
}

// Bump increases the version based on the version type
func (sv *SemanticVersion) Bump(versionType VersionType) *SemanticVersion {
	newVersion := &SemanticVersion{
		Major:      sv.Major,
		Minor:      sv.Minor,
		Patch:      sv.Patch,
		PreRelease: sv.PreRelease,
		BuildMeta:  sv.BuildMeta,
	}

	switch versionType {
	case PatchVersion:
		newVersion.Patch++
	case MinorVersion:
		newVersion.Minor++
		newVersion.Patch = 0
	case MajorVersion:
		newVersion.Major++
		newVersion.Minor = 0
		newVersion.Patch = 0
	}

	// Clear pre-release and build metadata on version bump
	newVersion.PreRelease = ""
	newVersion.BuildMeta = ""

	return newVersion
}

// CompareVersions compares two semantic versions
// Returns -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
func CompareVersions(v1, v2 *SemanticVersion) int {
	if v1.Major != v2.Major {
		if v1.Major < v2.Major {
			return -1
		}
		return 1
	}

	if v1.Minor != v2.Minor {
		if v1.Minor < v2.Minor {
			return -1
		}
		return 1
	}

	if v1.Patch != v2.Patch {
		if v1.Patch < v2.Patch {
			return -1
		}
		return 1
	}

	return 0
}

// AnalyzeCommitMessage analyzes a commit message and returns the change type
func AnalyzeCommitMessage(message string) ChangeType {
	message = strings.TrimSpace(message)
	
	// Check for breaking changes first
	if conventionalCommitPatterns[ChangeTypeBreaking].MatchString(message) {
		return ChangeTypeBreaking
	}

	// Check other patterns
	for changeType, pattern := range conventionalCommitPatterns {
		if changeType == ChangeTypeBreaking {
			continue // Already checked
		}
		if pattern.MatchString(message) {
			return changeType
		}
	}

	// Default to chore if no pattern matches
	return ChangeTypeChore
}

// DetermineVersionBump determines the version bump based on commit messages
func DetermineVersionBump(commitMessages []string) VersionType {
	hasBreaking := false
	hasFeat := false
	hasFix := false

	for _, message := range commitMessages {
		changeType := AnalyzeCommitMessage(message)
		
		switch changeType {
		case ChangeTypeBreaking:
			hasBreaking = true
		case ChangeTypeFeat:
			hasFeat = true
		case ChangeTypeFix, ChangeTypePerf:
			hasFix = true
		}
	}

	if hasBreaking {
		return MajorVersion
	}
	if hasFeat {
		return MinorVersion
	}
	if hasFix {
		return PatchVersion
	}

	// Default to patch for any other changes
	return PatchVersion
}

// CalculateNextVersion calculates the next version based on current version and commits
func CalculateNextVersion(currentVersion string, commitMessages []string) (*SemanticVersion, error) {
	current, err := ParseVersion(currentVersion)
	if err != nil {
		return nil, fmt.Errorf("failed to parse current version: %w", err)
	}

	versionType := DetermineVersionBump(commitMessages)
	return current.Bump(versionType), nil
}