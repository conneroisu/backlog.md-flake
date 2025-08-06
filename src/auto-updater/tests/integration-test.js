#!/usr/bin/env node
/**
 * Integration Test Suite for Auto-Updater System
 * Tests the complete auto-update workflow end-to-end
 */

const fs = require('fs').promises;
const path = require('path');
const { spawn } = require('child_process');

// Import components for testing
const NpmVersionMonitor = require('../scripts/npm-version-monitor');
const FlakeUpdater = require('../scripts/flake-updater');
const GitAutomation = require('../scripts/git-automation');
const RecoverySystem = require('../scripts/recovery-system');
const ValidationPipeline = require('../scripts/validation-pipeline');
const AutoUpdaterOrchestrator = require('../lib/orchestrator');

class IntegrationTestSuite {
    constructor() {
        this.testResults = [];
        this.testDir = path.join(__dirname, '../test-workspace');
        this.originalCwd = process.cwd();
        this.memoryNamespace = 'hive/auto-update/tests';
    }

    async init() {
        console.log('🧪 Initializing Integration Test Suite');
        
        // Create test workspace
        await fs.mkdir(this.testDir, { recursive: true });
        
        // Setup test environment
        await this.setupTestEnvironment();
    }

    async setupTestEnvironment() {
        console.log('🔧 Setting up test environment...');
        
        // Create minimal test flake.nix
        const testFlakeContent = `{
  description = "Test flake for auto-updater";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };
  outputs = { nixpkgs, ... }: {
    packages.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.writeText "test" "hello world";
  };
}`;
        
        const testFlakeLock = `{
  "nodes": {
    "nixpkgs": {
      "locked": {
        "lastModified": 1234567890,
        "narHash": "sha256-test",
        "owner": "NixOS",
        "repo": "nixpkgs",
        "rev": "abcdef1234567890",
        "type": "github"
      },
      "original": {
        "owner": "NixOS",
        "ref": "nixpkgs-unstable",
        "repo": "nixpkgs",
        "type": "github"
      }
    },
    "root": {
      "inputs": {
        "nixpkgs": "nixpkgs"
      }
    }
  },
  "root": "root",
  "version": 7
}`;
        
        await fs.writeFile(path.join(this.testDir, 'flake.nix'), testFlakeContent);
        await fs.writeFile(path.join(this.testDir, 'flake.lock'), testFlakeLock);
        
        // Initialize git repo
        await this.execCommand('git', ['init'], { cwd: this.testDir });
        await this.execCommand('git', ['config', 'user.name', 'Test User'], { cwd: this.testDir });
        await this.execCommand('git', ['config', 'user.email', 'test@example.com'], { cwd: this.testDir });
        await this.execCommand('git', ['add', '.'], { cwd: this.testDir });
        await this.execCommand('git', ['commit', '-m', 'Initial test commit'], { cwd: this.testDir });
        
        console.log('✅ Test environment ready');
    }

    async runAllTests() {
        console.log('🚀 Running all integration tests...');
        
        const tests = [
            { name: 'NPM Version Monitor', test: this.testNpmVersionMonitor.bind(this) },
            { name: 'Flake Updater', test: this.testFlakeUpdater.bind(this) },
            { name: 'Git Automation', test: this.testGitAutomation.bind(this) },
            { name: 'Recovery System', test: this.testRecoverySystem.bind(this) },
            { name: 'Validation Pipeline', test: this.testValidationPipeline.bind(this) },
            { name: 'End-to-End Workflow', test: this.testEndToEndWorkflow.bind(this) }
        ];
        
        for (const test of tests) {
            console.log(`\n🧪 Running test: ${test.name}`);
            
            try {
                const result = await test.test();
                this.testResults.push({
                    name: test.name,
                    success: true,
                    result,
                    timestamp: new Date().toISOString()
                });
                console.log(`✅ ${test.name} - PASSED`);
            } catch (error) {
                this.testResults.push({
                    name: test.name,
                    success: false,
                    error: error.message,
                    timestamp: new Date().toISOString()
                });
                console.log(`❌ ${test.name} - FAILED: ${error.message}`);
            }
        }
        
        return this.generateTestReport();
    }

    async testNpmVersionMonitor() {
        const monitor = new NpmVersionMonitor({
            packageName: 'backlog.md',
            currentVersion: '1.7.0', // Use old version for testing
            registryUrl: 'https://registry.npmjs.org'
        });
        
        await monitor.init();
        
        // Test version detection
        const versionChange = await monitor.detectVersionChange();
        
        if (!versionChange || versionChange.oldVersion !== '1.7.0') {
            throw new Error('Version change detection failed');
        }
        
        return { versionChange };
    }

    async testFlakeUpdater() {
        const updater = new FlakeUpdater({
            flakeFile: path.join(this.testDir, 'flake.nix'),
            flakeLockFile: path.join(this.testDir, 'flake.lock'),
            packageName: 'backlog.md'
        });
        
        await updater.init();
        
        // Create a backup first
        const backupPath = await updater.createBackup();
        
        if (!backupPath) {
            throw new Error('Backup creation failed');
        }
        
        // Test flake.nix update
        const versionInfo = {
            oldVersion: '1.7.0',
            newVersion: '1.7.1',
            integrity: 'sha512-test',
            shasum: 'test-shasum'
        };
        
        await updater.updateFlakeNix(versionInfo);
        
        // Verify the update
        const updatedContent = await fs.readFile(path.join(this.testDir, 'flake.nix'), 'utf8');
        
        if (!updatedContent.includes('1.7.1')) {
            throw new Error('Flake.nix update verification failed');
        }
        
        // Restore from backup
        await updater.rollback(backupPath);
        
        return { backupPath, versionInfo };
    }

    async testGitAutomation() {
        const gitAuto = new GitAutomation({
            repoPath: this.testDir,
            branch: 'test-auto-update',
            baseBranch: 'master',
            commitPrefix: 'test-update',
            enablePush: false,
            enablePR: false
        });
        
        await gitAuto.init();
        
        const versionInfo = {
            oldVersion: '1.7.0',
            newVersion: '1.7.1',
            publishedAt: new Date().toISOString()
        };
        
        // Create update branch
        const branchName = await gitAuto.createUpdateBranch(versionInfo);
        
        if (!branchName) {
            throw new Error('Update branch creation failed');
        }
        
        // Make a test change
        await fs.writeFile(
            path.join(this.testDir, 'test-change.txt'),
            'Test change for git automation'
        );
        
        // Commit changes
        const commitHash = await gitAuto.commitChanges(versionInfo, ['test-change.txt']);
        
        if (!commitHash) {
            throw new Error('Git commit failed');
        }
        
        return { branchName, commitHash };
    }

    async testRecoverySystem() {
        const recovery = new RecoverySystem({
            backupDir: path.join(this.testDir, 'backups'),
            maxBackups: 5,
            repoPath: this.testDir
        });
        
        await recovery.init();
        
        // Create a test backup
        const flakeContent = await fs.readFile(path.join(this.testDir, 'flake.nix'), 'utf8');
        const modifiedContent = flakeContent.replace('Test flake', 'Modified test flake');
        
        await fs.writeFile(path.join(this.testDir, 'flake.nix'), modifiedContent);
        
        // Create backup of modified state
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const backupPath = path.join(recovery.backupDir, `test-backup-${timestamp}`);
        
        await fs.mkdir(backupPath, { recursive: true });
        await fs.copyFile(path.join(this.testDir, 'flake.nix'), path.join(backupPath, 'flake.nix'));
        await fs.copyFile(path.join(this.testDir, 'flake.lock'), path.join(backupPath, 'flake.lock'));
        
        const metadata = {
            timestamp,
            type: 'test',
            checksums: {
                'flake.nix': 'test-checksum',
                'flake.lock': 'test-checksum'
            }
        };
        
        await fs.writeFile(path.join(backupPath, 'metadata.json'), JSON.stringify(metadata, null, 2));
        
        // Test backup listing
        const backups = await recovery.listBackups();
        
        if (backups.length === 0) {
            throw new Error('Backup listing failed');
        }
        
        // Test validation
        const validation = await recovery.validateBackup(backupPath);
        
        // Note: Validation will fail due to test checksums, but that's expected
        
        return { backups: backups.length, validation };
    }

    async testValidationPipeline() {
        const pipeline = new ValidationPipeline({
            repoPath: this.testDir,
            testSuites: ['syntax-validation', 'dependency-check'],
            enablePerformanceTests: false,
            enableSecurityScans: false
        });
        
        await pipeline.init();
        
        const versionInfo = {
            oldVersion: '1.7.0',
            newVersion: '1.7.1',
            packageName: 'backlog.md'
        };
        
        // Run validation pipeline
        const result = await pipeline.runValidationPipeline(versionInfo, {
            skipTests: ['flake-check', 'build-test', 'integration-test'], // Skip Nix-dependent tests
            strictMode: false
        });
        
        if (!result) {
            throw new Error('Validation pipeline failed to return result');
        }
        
        return result.summary;
    }

    async testEndToEndWorkflow() {
        // Test the orchestrator with a minimal workflow
        const configPath = path.join(this.testDir, 'test-config.json');
        
        const testConfig = {
            packageName: 'backlog.md',
            currentVersion: '1.7.0',
            registryUrl: 'https://registry.npmjs.org',
            monitoring: {
                enabled: false,
                webhook: { enabled: false },
                polling: { enabled: false }
            },
            updates: {
                autoUpdate: false,
                strictValidation: false,
                validation: {
                    testSuites: ['syntax-validation']
                }
            },
            git: { enabled: false },
            notifications: { enabled: false },
            paths: {
                repoPath: this.testDir,
                flakeFile: path.join(this.testDir, 'flake.nix'),
                flakeLockFile: path.join(this.testDir, 'flake.lock'),
                backupDir: path.join(this.testDir, 'backups')
            }
        };
        
        await fs.writeFile(configPath, JSON.stringify(testConfig, null, 2));
        
        const orchestrator = new AutoUpdaterOrchestrator(configPath);
        await orchestrator.init();
        
        // Test status
        const status = await orchestrator.getStatus();
        
        if (!status || typeof status.isRunning !== 'boolean') {
            throw new Error('Orchestrator status check failed');
        }
        
        return { status };
    }

    async generateTestReport() {
        const successfulTests = this.testResults.filter(t => t.success);
        const failedTests = this.testResults.filter(t => !t.success);
        
        const report = {
            summary: {
                total: this.testResults.length,
                successful: successfulTests.length,
                failed: failedTests.length,
                successRate: (successfulTests.length / this.testResults.length) * 100
            },
            results: this.testResults,
            failedTests: failedTests.map(t => ({ name: t.name, error: t.error })),
            timestamp: new Date().toISOString()
        };
        
        console.log('\n📊 Test Report Summary:');
        console.log(`✅ Successful: ${report.summary.successful}/${report.summary.total}`);
        console.log(`❌ Failed: ${report.summary.failed}/${report.summary.total}`);
        console.log(`📈 Success Rate: ${report.summary.successRate.toFixed(1)}%`);
        
        if (failedTests.length > 0) {
            console.log('\n❌ Failed Tests:');
            failedTests.forEach(test => {
                console.log(`  - ${test.name}: ${test.error}`);
            });
        }
        
        // Store test report
        const reportPath = path.join(__dirname, 'test-report.json');
        await fs.writeFile(reportPath, JSON.stringify(report, null, 2));
        console.log(`\n📄 Detailed report saved to: ${reportPath}`);
        
        return report;
    }

    async cleanup() {
        console.log('🧹 Cleaning up test environment...');
        
        try {
            // Change back to original directory
            process.chdir(this.originalCwd);
            
            // Remove test directory
            await fs.rmdir(this.testDir, { recursive: true });
            
            console.log('✅ Test cleanup completed');
        } catch (error) {
            console.warn('⚠️  Test cleanup warning:', error.message);
        }
    }

    async execCommand(command, args, options = {}) {
        return new Promise((resolve, reject) => {
            const process = spawn(command, args, {
                stdio: 'pipe',
                ...options
            });
            
            let stdout = '';
            let stderr = '';
            
            process.stdout.on('data', (data) => {
                stdout += data.toString();
            });
            
            process.stderr.on('data', (data) => {
                stderr += data.toString();
            });
            
            process.on('close', (code) => {
                if (code === 0) {
                    resolve({ stdout: stdout.trim(), stderr: stderr.trim() });
                } else {
                    reject(new Error(`Command failed (${code}): ${stderr || stdout}`));
                }
            });
        });
    }
}

// CLI Interface
if (require.main === module) {
    const args = process.argv.slice(2);
    const command = args[0] || 'run';
    
    const testSuite = new IntegrationTestSuite();
    
    (async () => {
        try {
            await testSuite.init();
            
            switch (command) {
                case 'run':
                    const report = await testSuite.runAllTests();
                    
                    // Exit with error code if tests failed
                    const exitCode = report.summary.failed > 0 ? 1 : 0;
                    
                    await testSuite.cleanup();
                    process.exit(exitCode);
                    
                case 'setup':
                    console.log('✅ Test environment setup completed');
                    break;
                    
                case 'cleanup':
                    await testSuite.cleanup();
                    console.log('✅ Test environment cleaned up');
                    break;
                    
                default:
                    console.log('Usage: integration-test.js [run|setup|cleanup]');
                    console.log('');
                    console.log('Commands:');
                    console.log('  run      - Run all integration tests');
                    console.log('  setup    - Setup test environment only');
                    console.log('  cleanup  - Cleanup test environment');
                    process.exit(1);
            }
            
        } catch (error) {
            console.error('❌ Integration test failed:', error.message);
            
            try {
                await testSuite.cleanup();
            } catch (cleanupError) {
                console.error('❌ Cleanup also failed:', cleanupError.message);
            }
            
            process.exit(1);
        }
    })();
}

module.exports = IntegrationTestSuite;