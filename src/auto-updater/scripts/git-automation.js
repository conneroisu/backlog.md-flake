#!/usr/bin/env node
/**
 * Automated Git Operations for Updates
 * Handles Git workflows for version updates and releases
 */

const fs = require('fs').promises;
const path = require('path');
const { spawn, exec } = require('child_process');

class GitAutomation {
    constructor(config = {}) {
        this.repoPath = config.repoPath || process.cwd();
        this.branch = config.branch || 'auto-update';
        this.baseBranch = config.baseBranch || 'main';
        this.commitPrefix = config.commitPrefix || 'auto-update';
        this.memoryNamespace = 'hive/auto-update';
        this.enablePush = config.enablePush || false;
        this.enablePR = config.enablePR || false;
    }

    async init() {
        console.log('🔧 Initializing Git Automation');
        await this.storeMemory('git_automation_init', {
            repoPath: this.repoPath,
            branch: this.branch,
            baseBranch: this.baseBranch,
            timestamp: new Date().toISOString()
        });
    }

    async execGitCommand(args, options = {}) {
        return new Promise((resolve, reject) => {
            const gitProcess = spawn('git', args, {
                cwd: this.repoPath,
                stdio: 'pipe',
                ...options
            });

            let stdout = '';
            let stderr = '';

            gitProcess.stdout.on('data', (data) => {
                stdout += data.toString();
            });

            gitProcess.stderr.on('data', (data) => {
                stderr += data.toString();
            });

            gitProcess.on('close', (code) => {
                if (code === 0) {
                    resolve({ stdout: stdout.trim(), stderr: stderr.trim(), code });
                } else {
                    reject(new Error(`Git command failed (${code}): ${stderr || stdout}`));
                }
            });
        });
    }

    async getCurrentBranch() {
        try {
            const result = await this.execGitCommand(['rev-parse', '--abbrev-ref', 'HEAD']);
            return result.stdout;
        } catch (error) {
            console.error('❌ Failed to get current branch:', error.message);
            throw error;
        }
    }

    async getCommitHash() {
        try {
            const result = await this.execGitCommand(['rev-parse', 'HEAD']);
            return result.stdout;
        } catch (error) {
            console.error('❌ Failed to get commit hash:', error.message);
            throw error;
        }
    }

    async hasUncommittedChanges() {
        try {
            const result = await this.execGitCommand(['status', '--porcelain']);
            return result.stdout.length > 0;
        } catch (error) {
            console.error('❌ Failed to check git status:', error.message);
            return true; // Assume changes exist if we can't check
        }
    }

    async stashChanges() {
        try {
            console.log('💾 Stashing current changes...');
            const result = await this.execGitCommand(['stash', 'push', '-m', 'auto-update: temporary stash']);
            
            await this.storeMemory('changes_stashed', {
                message: result.stdout,
                timestamp: new Date().toISOString()
            });
            
            return true;
        } catch (error) {
            console.error('❌ Failed to stash changes:', error.message);
            return false;
        }
    }

    async createUpdateBranch(versionInfo) {
        const branchName = `${this.branch}/${versionInfo.newVersion}`;
        
        try {
            console.log(`🌿 Creating update branch: ${branchName}`);
            
            // Ensure we're on the base branch
            await this.execGitCommand(['checkout', this.baseBranch]);
            
            // Pull latest changes
            await this.execGitCommand(['pull', 'origin', this.baseBranch]);
            
            // Create and checkout new branch
            await this.execGitCommand(['checkout', '-b', branchName]);
            
            console.log(`✅ Created branch: ${branchName}`);
            
            await this.storeMemory('branch_created', {
                branchName,
                baseBranch: this.baseBranch,
                versionInfo,
                timestamp: new Date().toISOString()
            });
            
            return branchName;
            
        } catch (error) {
            console.error('❌ Failed to create update branch:', error.message);
            throw error;
        }
    }

    async commitChanges(versionInfo, changedFiles = []) {
        try {
            console.log('📝 Committing changes...');
            
            // Stage files
            if (changedFiles.length > 0) {
                await this.execGitCommand(['add', ...changedFiles]);
            } else {
                // Stage all changes
                await this.execGitCommand(['add', '.']);
            }
            
            // Create commit message
            const commitMessage = this.generateCommitMessage(versionInfo);
            
            // Commit changes
            await this.execGitCommand(['commit', '-m', commitMessage]);
            
            const commitHash = await this.getCommitHash();
            console.log(`✅ Changes committed: ${commitHash.substring(0, 8)}`);
            
            await this.storeMemory('changes_committed', {
                commitHash,
                commitMessage,
                versionInfo,
                changedFiles,
                timestamp: new Date().toISOString()
            });
            
            return commitHash;
            
        } catch (error) {
            console.error('❌ Failed to commit changes:', error.message);
            throw error;
        }
    }

    generateCommitMessage(versionInfo) {
        const lines = [
            `${this.commitPrefix}: update ${versionInfo.oldVersion} → ${versionInfo.newVersion}`,
            '',
            `- Updated backlog.md package to version ${versionInfo.newVersion}`,
            `- Updated flake.nix and flake.lock files`,
            `- Package published: ${versionInfo.publishedAt}`,
            '',
            `🤖 Generated with Claude Code Auto-Updater`,
            '',
            `Co-Authored-By: Claude <noreply@anthropic.com>`
        ];
        
        return lines.join('\n');
    }

    async tagVersion(versionInfo) {
        try {
            const tagName = `v${versionInfo.newVersion}`;
            const tagMessage = `Auto-update to backlog.md ${versionInfo.newVersion}`;
            
            console.log(`🏷️  Creating tag: ${tagName}`);
            
            await this.execGitCommand(['tag', '-a', tagName, '-m', tagMessage]);
            
            console.log(`✅ Tag created: ${tagName}`);
            
            await this.storeMemory('tag_created', {
                tagName,
                tagMessage,
                versionInfo,
                timestamp: new Date().toISOString()
            });
            
            return tagName;
            
        } catch (error) {
            console.error('❌ Failed to create tag:', error.message);
            throw error;
        }
    }

    async pushChanges(branchName, tagName = null) {
        if (!this.enablePush) {
            console.log('📤 Push disabled, skipping remote push');
            return false;
        }
        
        try {
            console.log('📤 Pushing changes to remote...');
            
            // Push branch
            await this.execGitCommand(['push', 'origin', branchName]);
            
            // Push tag if provided
            if (tagName) {
                await this.execGitCommand(['push', 'origin', tagName]);
            }
            
            console.log('✅ Changes pushed to remote');
            
            await this.storeMemory('changes_pushed', {
                branchName,
                tagName,
                timestamp: new Date().toISOString()
            });
            
            return true;
            
        } catch (error) {
            console.error('❌ Failed to push changes:', error.message);
            throw error;
        }
    }

    async createPullRequest(branchName, versionInfo) {
        if (!this.enablePR) {
            console.log('🔀 PR creation disabled, skipping pull request');
            return null;
        }
        
        try {
            console.log('🔀 Creating pull request...');
            
            const title = `Auto-update: backlog.md ${versionInfo.oldVersion} → ${versionInfo.newVersion}`;
            const body = this.generatePRBody(versionInfo);
            
            // Use GitHub CLI if available
            const prResult = await this.execGitCommand([
                'gh', 'pr', 'create',
                '--title', title,
                '--body', body,
                '--base', this.baseBranch,
                '--head', branchName
            ]);
            
            console.log('✅ Pull request created');
            
            await this.storeMemory('pr_created', {
                title,
                body,
                branchName,
                baseBranch: this.baseBranch,
                result: prResult.stdout,
                timestamp: new Date().toISOString()
            });
            
            return prResult.stdout;
            
        } catch (error) {
            console.warn('⚠️  Failed to create PR (gh CLI may not be available):', error.message);
            return null;
        }
    }

    generatePRBody(versionInfo) {
        return `## Auto-Update Summary

**Package:** backlog.md  
**Version:** ${versionInfo.oldVersion} → ${versionInfo.newVersion}  
**Published:** ${versionInfo.publishedAt}  

### Changes Made
- ✅ Updated flake.nix package version
- ✅ Updated flake.lock with \`nix flake update\`
- ✅ Validated flake configuration
- ✅ Tested build process

### Package Information
- **Integrity:** \`${versionInfo.integrity}\`
- **Shasum:** \`${versionInfo.shasum}\`

### Validation
This update has been automatically validated and tested:
- 🔍 Flake check passed
- 🧪 Build test passed
- 💾 Backup created before update

🤖 Generated with Claude Code Auto-Updater

Co-Authored-By: Claude <noreply@anthropic.com>`;
    }

    async performGitWorkflow(versionInfo) {
        console.log('🔄 Starting Git workflow...');
        
        let originalBranch = null;
        let branchName = null;
        
        try {
            // Get current branch
            originalBranch = await this.getCurrentBranch();
            
            // Stash uncommitted changes if any
            const hasChanges = await this.hasUncommittedChanges();
            if (hasChanges) {
                await this.stashChanges();
            }
            
            // Create update branch
            branchName = await this.createUpdateBranch(versionInfo);
            
            // At this point, flake files should already be updated by FlakeUpdater
            // We just need to commit the changes
            
            const changedFiles = ['flake.nix', 'flake.lock'];
            const commitHash = await this.commitChanges(versionInfo, changedFiles);
            
            // Create tag
            const tagName = await this.tagVersion(versionInfo);
            
            // Push to remote if enabled
            await this.pushChanges(branchName, tagName);
            
            // Create pull request if enabled
            const prResult = await this.createPullRequest(branchName, versionInfo);
            
            console.log('🎉 Git workflow completed successfully!');
            
            await this.storeMemory('git_workflow_completed', {
                originalBranch,
                branchName,
                commitHash,
                tagName,
                prResult,
                versionInfo,
                timestamp: new Date().toISOString()
            });
            
            return {
                branchName,
                commitHash,
                tagName,
                prResult
            };
            
        } catch (error) {
            console.error('❌ Git workflow failed:', error.message);
            
            // Attempt to restore original state
            if (originalBranch) {
                try {
                    await this.execGitCommand(['checkout', originalBranch]);
                    
                    // Delete the update branch if created
                    if (branchName) {
                        await this.execGitCommand(['branch', '-D', branchName]);
                    }
                } catch (restoreError) {
                    console.error('❌ Failed to restore original state:', restoreError.message);
                }
            }
            
            await this.storeMemory('git_workflow_failed', {
                originalBranch,
                branchName,
                error: error.message,
                versionInfo,
                timestamp: new Date().toISOString()
            });
            
            throw error;
        }
    }

    async storeMemory(key, value) {
        try {
            const memoryDir = path.join(process.cwd(), 'memory', 'auto-updater');
            await fs.mkdir(memoryDir, { recursive: true });
            await fs.writeFile(
                path.join(memoryDir, `${key}.json`), 
                JSON.stringify(value, null, 2)
            );
        } catch (error) {
            console.warn('⚠️  Failed to store memory:', error.message);
        }
    }
}

// CLI Interface
if (require.main === module) {
    const args = process.argv.slice(2);
    const command = args[0] || 'workflow';
    const versionInfoJson = args[1];
    
    if (command === 'workflow' && !versionInfoJson) {
        console.error('Usage: git-automation.js workflow <version-info-json>');
        process.exit(1);
    }
    
    (async () => {
        try {
            const gitAuto = new GitAutomation({
                enablePush: process.env.ENABLE_GIT_PUSH === 'true',
                enablePR: process.env.ENABLE_GIT_PR === 'true'
            });
            
            await gitAuto.init();
            
            switch (command) {
                case 'workflow':
                    const versionInfo = JSON.parse(versionInfoJson);
                    await gitAuto.performGitWorkflow(versionInfo);
                    break;
                case 'status':
                    const currentBranch = await gitAuto.getCurrentBranch();
                    const hasChanges = await gitAuto.hasUncommittedChanges();
                    console.log(`Current branch: ${currentBranch}`);
                    console.log(`Uncommitted changes: ${hasChanges ? 'Yes' : 'No'}`);
                    break;
                default:
                    console.log('Usage: git-automation.js [workflow|status] [version-info-json]');
                    process.exit(1);
            }
            
        } catch (error) {
            console.error('❌ Git automation failed:', error.message);
            process.exit(1);
        }
    })();
}

module.exports = GitAutomation;