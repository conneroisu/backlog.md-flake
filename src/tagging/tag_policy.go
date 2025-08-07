package tagging

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// TagPolicy defines policies for tag creation and validation
type TagPolicy struct {
	Rules           []TagRule           `json:"rules"`
	Enforcement     EnforcementLevel    `json:"enforcement"`
	AllowedBranches []string            `json:"allowed_branches"`
	RequiredChecks  []string            `json:"required_checks"`
	Versioning      VersioningPolicy    `json:"versioning"`
	Protection      ProtectionPolicy    `json:"protection"`
	Hooks           HookConfiguration   `json:"hooks"`
	Notifications   NotificationPolicy  `json:"notifications"`
}

// TagRule represents a single tagging rule
type TagRule struct {
	Name        string      `json:"name"`
	Description string      `json:"description"`
	Pattern     string      `json:"pattern"`
	Type        RuleType    `json:"type"`
	Severity    Severity    `json:"severity"`
	Enabled     bool        `json:"enabled"`
	Conditions  []Condition `json:"conditions"`
}

// EnforcementLevel defines how strictly policies are enforced
type EnforcementLevel string

const (
	EnforcementNone    EnforcementLevel = "none"
	EnforcementWarn    EnforcementLevel = "warn"
	EnforcementBlock   EnforcementLevel = "block"
	EnforcementStrict  EnforcementLevel = "strict"
)

// RuleType defines the type of validation rule
type RuleType string

const (
	RuleTypeFormat     RuleType = "format"
	RuleTypeSequence   RuleType = "sequence"
	RuleTypeBranch     RuleType = "branch"
	RuleTypeCommit     RuleType = "commit"
	RuleTypePermission RuleType = "permission"
	RuleTypeCI         RuleType = "ci"
)

// Severity defines the severity level of a rule violation
type Severity string

const (
	SeverityInfo    Severity = "info"
	SeverityWarning Severity = "warning"
	SeverityError   Severity = "error"
	SeverityCritical Severity = "critical"
)

// Condition represents a conditional check for a rule
type Condition struct {
	Field    string      `json:"field"`
	Operator string      `json:"operator"`
	Value    interface{} `json:"value"`
}

// VersioningPolicy defines versioning requirements
type VersioningPolicy struct {
	Scheme              string   `json:"scheme"`                // "semver", "calver", "custom"
	AllowPreRelease     bool     `json:"allow_prerelease"`
	RequireAnnotation   bool     `json:"require_annotation"`
	ForbiddenPatterns   []string `json:"forbidden_patterns"`
	MandatoryComponents []string `json:"mandatory_components"`
	IncrementRules      []string `json:"increment_rules"`
}

// ProtectionPolicy defines tag protection settings
type ProtectionPolicy struct {
	ProtectedTags   []string `json:"protected_tags"`
	AllowDeletion   bool     `json:"allow_deletion"`
	AllowForcing    bool     `json:"allow_forcing"`
	RequireSignature bool    `json:"require_signature"`
	RequireReviewer bool     `json:"require_reviewer"`
	MinReviewers    int      `json:"min_reviewers"`
}

// HookConfiguration defines pre/post tag hooks
type HookConfiguration struct {
	PreTag  []HookConfig `json:"pre_tag"`
	PostTag []HookConfig `json:"post_tag"`
}

// HookConfig represents a single hook configuration
type HookConfig struct {
	Name    string            `json:"name"`
	Command string            `json:"command"`
	Env     map[string]string `json:"env"`
	Timeout int               `json:"timeout"`
	OnError string            `json:"on_error"` // "fail", "warn", "ignore"
}

// NotificationPolicy defines notification settings
type NotificationPolicy struct {
	Enabled   bool     `json:"enabled"`
	Channels  []string `json:"channels"` // "email", "slack", "webhook"
	Templates []string `json:"templates"`
	Events    []string `json:"events"` // "tag_created", "tag_deleted", "violation"
}

// PolicyValidator validates tagging operations against policies
type PolicyValidator struct {
	Policy     *TagPolicy
	ConfigPath string
}

// PolicyViolation represents a policy violation
type PolicyViolation struct {
	Rule        string    `json:"rule"`
	Message     string    `json:"message"`
	Severity    Severity  `json:"severity"`
	Field       string    `json:"field,omitempty"`
	Value       string    `json:"value,omitempty"`
	Suggestion  string    `json:"suggestion,omitempty"`
	Timestamp   time.Time `json:"timestamp"`
	Remediation string    `json:"remediation,omitempty"`
}

// PolicyResult represents the result of policy validation
type PolicyResult struct {
	Valid       bool               `json:"valid"`
	Violations  []PolicyViolation  `json:"violations"`
	Warnings    []PolicyViolation  `json:"warnings"`
	Approved    bool               `json:"approved"`
	Summary     PolicySummary      `json:"summary"`
}

// PolicySummary provides a summary of policy validation results
type PolicySummary struct {
	TotalRules      int `json:"total_rules"`
	PassedRules     int `json:"passed_rules"`
	FailedRules     int `json:"failed_rules"`
	CriticalIssues  int `json:"critical_issues"`
	WarningIssues   int `json:"warning_issues"`
}

// NewPolicyValidator creates a new policy validator
func NewPolicyValidator(configPath string) (*PolicyValidator, error) {
	validator := &PolicyValidator{
		ConfigPath: configPath,
	}

	if err := validator.LoadPolicy(); err != nil {
		return nil, fmt.Errorf("failed to load policy: %w", err)
	}

	return validator, nil
}

// LoadPolicy loads the tagging policy from configuration file
func (pv *PolicyValidator) LoadPolicy() error {
	if pv.ConfigPath == "" {
		pv.Policy = pv.getDefaultPolicy()
		return nil
	}

	data, err := os.ReadFile(pv.ConfigPath)
	if err != nil {
		if os.IsNotExist(err) {
			pv.Policy = pv.getDefaultPolicy()
			return nil
		}
		return fmt.Errorf("failed to read policy file: %w", err)
	}

	var policy TagPolicy
	if err := json.Unmarshal(data, &policy); err != nil {
		return fmt.Errorf("failed to parse policy file: %w", err)
	}

	pv.Policy = &policy
	return nil
}

// getDefaultPolicy returns a default tagging policy
func (pv *PolicyValidator) getDefaultPolicy() *TagPolicy {
	return &TagPolicy{
		Rules: []TagRule{
			{
				Name:        "semver_format",
				Description: "Tag must follow semantic versioning format",
				Pattern:     `^v([0-9]+)\.([0-9]+)\.([0-9]+)(?:-([0-9A-Za-z\-]+(?:\.[0-9A-Za-z\-]+)*))?(?:\+([0-9A-Za-z\-]+(?:\.[0-9A-Za-z\-]+)*))?$`,
				Type:        RuleTypeFormat,
				Severity:    SeverityError,
				Enabled:     true,
			},
			{
				Name:        "no_duplicate_tags",
				Description: "Tag must not already exist",
				Type:        RuleTypeSequence,
				Severity:    SeverityError,
				Enabled:     true,
			},
			{
				Name:        "main_branch_only",
				Description: "Tags can only be created from main branch",
				Type:        RuleTypeBranch,
				Severity:    SeverityWarning,
				Enabled:     true,
				Conditions: []Condition{
					{
						Field:    "branch",
						Operator: "in",
						Value:    []string{"main", "master", "release"},
					},
				},
			},
			{
				Name:        "require_changelog",
				Description: "Release must have changelog entry",
				Type:        RuleTypeCommit,
				Severity:    SeverityWarning,
				Enabled:     true,
			},
		},
		Enforcement:     EnforcementWarn,
		AllowedBranches: []string{"main", "master", "release"},
		RequiredChecks:  []string{"build", "test"},
		Versioning: VersioningPolicy{
			Scheme:              "semver",
			AllowPreRelease:     true,
			RequireAnnotation:   true,
			ForbiddenPatterns:   []string{"latest", "HEAD"},
			MandatoryComponents: []string{"major", "minor", "patch"},
		},
		Protection: ProtectionPolicy{
			ProtectedTags:    []string{"v*"},
			AllowDeletion:    false,
			AllowForcing:     false,
			RequireSignature: false,
			RequireReviewer:  false,
		},
		Notifications: NotificationPolicy{
			Enabled:  false,
			Channels: []string{},
			Events:   []string{"tag_created", "violation"},
		},
	}
}

// ValidateTag validates a tag creation against the policy
func (pv *PolicyValidator) ValidateTag(tagName, branch, message string, tagger *GitTagger) *PolicyResult {
	result := &PolicyResult{
		Valid:      true,
		Violations: []PolicyViolation{},
		Warnings:   []PolicyViolation{},
		Approved:   false,
	}

	// Validate each rule
	for _, rule := range pv.Policy.Rules {
		if !rule.Enabled {
			continue
		}

		violation := pv.validateRule(rule, tagName, branch, message, tagger)
		if violation != nil {
			if violation.Severity == SeverityError || violation.Severity == SeverityCritical {
				result.Violations = append(result.Violations, *violation)
				result.Valid = false
			} else {
				result.Warnings = append(result.Warnings, *violation)
			}
		}
	}

	// Calculate summary
	result.Summary = pv.calculateSummary(result)

	// Determine approval based on enforcement level
	result.Approved = pv.determineApproval(result)

	return result
}

// validateRule validates a single rule
func (pv *PolicyValidator) validateRule(rule TagRule, tagName, branch, message string, tagger *GitTagger) *PolicyViolation {
	switch rule.Type {
	case RuleTypeFormat:
		return pv.validateFormat(rule, tagName)
	case RuleTypeSequence:
		return pv.validateSequence(rule, tagName, tagger)
	case RuleTypeBranch:
		return pv.validateBranch(rule, branch)
	case RuleTypeCommit:
		return pv.validateCommit(rule, message, tagger)
	case RuleTypeCI:
		return pv.validateCI(rule, tagName, tagger)
	default:
		return nil
	}
}

// validateFormat validates tag name format
func (pv *PolicyValidator) validateFormat(rule TagRule, tagName string) *PolicyViolation {
	if rule.Pattern == "" {
		return nil
	}

	matched, err := regexp.MatchString(rule.Pattern, tagName)
	if err != nil {
		return &PolicyViolation{
			Rule:      rule.Name,
			Message:   fmt.Sprintf("Invalid regex pattern: %s", err.Error()),
			Severity:  SeverityError,
			Field:     "pattern",
			Value:     rule.Pattern,
			Timestamp: time.Now(),
		}
	}

	if !matched {
		return &PolicyViolation{
			Rule:        rule.Name,
			Message:     fmt.Sprintf("Tag name '%s' does not match required pattern", tagName),
			Severity:    rule.Severity,
			Field:       "tag_name",
			Value:       tagName,
			Suggestion:  pv.suggestFormat(rule.Pattern),
			Timestamp:   time.Now(),
			Remediation: "Please use a tag name that follows the required format",
		}
	}

	return nil
}

// validateSequence validates tag sequence (no duplicates, proper ordering)
func (pv *PolicyValidator) validateSequence(rule TagRule, tagName string, tagger *GitTagger) *PolicyViolation {
	if rule.Name == "no_duplicate_tags" {
		if tagger.TagExists(tagName) {
			return &PolicyViolation{
				Rule:        rule.Name,
				Message:     fmt.Sprintf("Tag '%s' already exists", tagName),
				Severity:    rule.Severity,
				Field:       "tag_name",
				Value:       tagName,
				Timestamp:   time.Now(),
				Remediation: "Choose a different tag name or delete the existing tag",
			}
		}
	}

	return nil
}

// validateBranch validates branch constraints
func (pv *PolicyValidator) validateBranch(rule TagRule, branch string) *PolicyViolation {
	if len(pv.Policy.AllowedBranches) == 0 {
		return nil
	}

	for _, allowedBranch := range pv.Policy.AllowedBranches {
		if branch == allowedBranch {
			return nil
		}
	}

	return &PolicyViolation{
		Rule:        rule.Name,
		Message:     fmt.Sprintf("Tags can only be created from allowed branches. Current: %s, Allowed: %v", branch, pv.Policy.AllowedBranches),
		Severity:    rule.Severity,
		Field:       "branch",
		Value:       branch,
		Timestamp:   time.Now(),
		Remediation: fmt.Sprintf("Switch to one of the allowed branches: %s", strings.Join(pv.Policy.AllowedBranches, ", ")),
	}
}

// validateCommit validates commit-related requirements
func (pv *PolicyValidator) validateCommit(rule TagRule, message string, tagger *GitTagger) *PolicyViolation {
	if rule.Name == "require_changelog" {
		// Check if CHANGELOG.md exists and has been modified recently
		changelogPath := filepath.Join(tagger.RepoPath, "CHANGELOG.md")
		if _, err := os.Stat(changelogPath); os.IsNotExist(err) {
			return &PolicyViolation{
				Rule:        rule.Name,
				Message:     "CHANGELOG.md file is required but not found",
				Severity:    rule.Severity,
				Field:       "changelog",
				Timestamp:   time.Now(),
				Remediation: "Create a CHANGELOG.md file and document the changes for this release",
			}
		}
	}

	return nil
}

// validateCI validates CI/CD related requirements
func (pv *PolicyValidator) validateCI(rule TagRule, tagName string, tagger *GitTagger) *PolicyViolation {
	// This would check CI status via GitHub API or other CI systems
	// For now, return nil (validation passes)
	return nil
}

// suggestFormat provides a format suggestion based on the pattern
func (pv *PolicyValidator) suggestFormat(pattern string) string {
	suggestions := map[string]string{
		`^v([0-9]+)\.([0-9]+)\.([0-9]+)`: "Use format: v1.0.0",
		`^([0-9]+)\.([0-9]+)\.([0-9]+)`:  "Use format: 1.0.0",
		`^release-.*`:                    "Use format: release-v1.0.0",
	}

	for pat, suggestion := range suggestions {
		if strings.Contains(pattern, pat) {
			return suggestion
		}
	}

	return "Please follow the required tag format"
}

// calculateSummary calculates the policy validation summary
func (pv *PolicyValidator) calculateSummary(result *PolicyResult) PolicySummary {
	totalRules := len(pv.Policy.Rules)
	failedRules := len(result.Violations)
	passedRules := totalRules - failedRules
	
	criticalIssues := 0
	warningIssues := 0

	for _, violation := range result.Violations {
		if violation.Severity == SeverityCritical {
			criticalIssues++
		}
	}

	for _, warning := range result.Warnings {
		if warning.Severity == SeverityWarning {
			warningIssues++
		}
	}

	return PolicySummary{
		TotalRules:     totalRules,
		PassedRules:    passedRules,
		FailedRules:    failedRules,
		CriticalIssues: criticalIssues,
		WarningIssues:  warningIssues,
	}
}

// determineApproval determines if the tag is approved based on enforcement level
func (pv *PolicyValidator) determineApproval(result *PolicyResult) bool {
	switch pv.Policy.Enforcement {
	case EnforcementNone:
		return true
	case EnforcementWarn:
		return len(result.Violations) == 0
	case EnforcementBlock:
		return result.Valid && result.Summary.CriticalIssues == 0
	case EnforcementStrict:
		return result.Valid && len(result.Warnings) == 0
	default:
		return result.Valid
	}
}

// SavePolicy saves the current policy to file
func (pv *PolicyValidator) SavePolicy() error {
	if pv.ConfigPath == "" {
		return fmt.Errorf("no config path specified")
	}

	// Ensure directory exists
	dir := filepath.Dir(pv.ConfigPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}

	data, err := json.MarshalIndent(pv.Policy, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal policy: %w", err)
	}

	if err := os.WriteFile(pv.ConfigPath, data, 0644); err != nil {
		return fmt.Errorf("failed to write policy file: %w", err)
	}

	return nil
}

// UpdateRule updates a specific rule in the policy
func (pv *PolicyValidator) UpdateRule(ruleName string, updates map[string]interface{}) error {
	for i, rule := range pv.Policy.Rules {
		if rule.Name == ruleName {
			// Update rule fields based on the updates map
			if pattern, ok := updates["pattern"].(string); ok {
				pv.Policy.Rules[i].Pattern = pattern
			}
			if enabled, ok := updates["enabled"].(bool); ok {
				pv.Policy.Rules[i].Enabled = enabled
			}
			if severity, ok := updates["severity"].(string); ok {
				pv.Policy.Rules[i].Severity = Severity(severity)
			}
			if description, ok := updates["description"].(string); ok {
				pv.Policy.Rules[i].Description = description
			}
			return nil
		}
	}

	return fmt.Errorf("rule not found: %s", ruleName)
}

// AddRule adds a new rule to the policy
func (pv *PolicyValidator) AddRule(rule TagRule) {
	pv.Policy.Rules = append(pv.Policy.Rules, rule)
}

// RemoveRule removes a rule from the policy
func (pv *PolicyValidator) RemoveRule(ruleName string) error {
	for i, rule := range pv.Policy.Rules {
		if rule.Name == ruleName {
			pv.Policy.Rules = append(pv.Policy.Rules[:i], pv.Policy.Rules[i+1:]...)
			return nil
		}
	}
	return fmt.Errorf("rule not found: %s", ruleName)
}

// ValidatePolicy validates the policy configuration itself
func (pv *PolicyValidator) ValidatePolicy() []PolicyViolation {
	var violations []PolicyViolation

	// Check for duplicate rule names
	ruleNames := make(map[string]bool)
	for _, rule := range pv.Policy.Rules {
		if ruleNames[rule.Name] {
			violations = append(violations, PolicyViolation{
				Rule:      "policy_validation",
				Message:   fmt.Sprintf("Duplicate rule name: %s", rule.Name),
				Severity:  SeverityError,
				Field:     "rule_name",
				Value:     rule.Name,
				Timestamp: time.Now(),
			})
		}
		ruleNames[rule.Name] = true

		// Validate regex patterns
		if rule.Pattern != "" {
			if _, err := regexp.Compile(rule.Pattern); err != nil {
				violations = append(violations, PolicyViolation{
					Rule:      rule.Name,
					Message:   fmt.Sprintf("Invalid regex pattern: %s", err.Error()),
					Severity:  SeverityError,
					Field:     "pattern",
					Value:     rule.Pattern,
					Timestamp: time.Now(),
				})
			}
		}
	}

	return violations
}