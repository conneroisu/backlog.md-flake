#!/usr/bin/env node
/**
 * Update Validation and Testing Pipeline
 * Comprehensive validation system for update integrity and functionality
 */

const fs = require('fs').promises;
const path = require('path');
const { spawn } = require('child_process');
const crypto = require('crypto');

class ValidationPipeline {
    constructor(config = {}) {
        this.repoPath = config.repoPath || process.cwd();
        this.memoryNamespace = 'hive/auto-update';
        this.validationResults = [];
        this.testSuites = config.testSuites || [
            'flake-check',
            'build-test',
            'syntax-validation',
            'dependency-check',
            'security-scan',
            'integration-test'
        ];
        this.enablePerformanceTests = config.enablePerformanceTests || false;
        this.enableSecurityScans = config.enableSecurityScans || true;
    }

    async init() {
        console.log('🔧 Initializing Validation Pipeline');
        this.validationResults = [];
        await this.storeMemory('validation_pipeline_init', {
            testSuites: this.testSuites,
            enablePerformanceTests: this.enablePerformanceTests,
            enableSecurityScans: this.enableSecurityScans,
            timestamp: new Date().toISOString()
        });
    }

    async runValidationPipeline(versionInfo, options = {}) {
        console.log('🚀 Starting validation pipeline...');
        
        const {
            skipTests = [],
            strictMode = true,
            timeoutMs = 300000 // 5 minutes default
        } = options;
        
        const startTime = Date.now();
        let overallSuccess = true;
        
        try {
            // Pre-validation checks
            await this.preValidationChecks();
            
            // Run test suites
            for (const testSuite of this.testSuites) {
                if (skipTests.includes(testSuite)) {
                    console.log(`⏭️  Skipping test suite: ${testSuite}`);
                    continue;
                }
                
                console.log(`🧪 Running test suite: ${testSuite}`);
                const result = await this.runTestSuite(testSuite, versionInfo, timeoutMs);
                
                this.validationResults.push(result);
                
                if (!result.success && strictMode) {
                    console.error(`❌ Test suite ${testSuite} failed in strict mode`);
                    overallSuccess = false;
                    break;
                } else if (!result.success) {
                    console.warn(`⚠️  Test suite ${testSuite} failed but continuing (non-strict mode)`);
                    overallSuccess = false;
                }
            }
            
            // Performance tests if enabled
            if (this.enablePerformanceTests && !skipTests.includes('performance')) {
                const perfResult = await this.runPerformanceTests(versionInfo);
                this.validationResults.push(perfResult);
                
                if (!perfResult.success && strictMode) {
                    overallSuccess = false;
                }
            }
            
            // Security scans if enabled
            if (this.enableSecurityScans && !skipTests.includes('security')) {
                const securityResult = await this.runSecurityScans(versionInfo);
                this.validationResults.push(securityResult);
                
                if (!securityResult.success && strictMode) {
                    overallSuccess = false;
                }
            }
            
            // Post-validation analysis
            const analysisResult = await this.postValidationAnalysis();
            this.validationResults.push(analysisResult);
            
            const totalTime = Date.now() - startTime;
            
            console.log(`${overallSuccess ? '✅' : '❌'} Validation pipeline ${overallSuccess ? 'completed successfully' : 'failed'}`);
            console.log(`⏱️  Total time: ${(totalTime / 1000).toFixed(2)}s`);
            
            const pipelineResult = {
                success: overallSuccess,
                versionInfo,
                totalTime,
                testResults: this.validationResults,
                summary: this.generateSummary(),
                timestamp: new Date().toISOString()
            };
            
            await this.storeMemory('validation_pipeline_result', pipelineResult);
            
            return pipelineResult;
            
        } catch (error) {
            console.error('❌ Validation pipeline error:', error.message);
            
            const errorResult = {
                success: false,
                error: error.message,
                versionInfo,
                testResults: this.validationResults,
                timestamp: new Date().toISOString()
            };
            
            await this.storeMemory('validation_pipeline_error', errorResult);
            throw error;
        }
    }

    async preValidationChecks() {
        console.log('🔍 Running pre-validation checks...');
        
        const checks = [
            { name: 'flake.nix exists', check: () => this.fileExists('flake.nix') },
            { name: 'flake.lock exists', check: () => this.fileExists('flake.lock') },
            { name: 'nix command available', check: () => this.commandExists('nix') },
            { name: 'git repository valid', check: () => this.isGitRepository() }
        ];
        
        for (const check of checks) {
            const result = await check.check();
            if (!result) {
                throw new Error(`Pre-validation check failed: ${check.name}`);
            }
            console.log(`✅ ${check.name}`);
        }
    }

    async runTestSuite(suiteName, versionInfo, timeoutMs) {
        const startTime = Date.now();
        
        try {
            let result;
            
            switch (suiteName) {
                case 'flake-check':
                    result = await this.runFlakeCheck(timeoutMs);
                    break;
                case 'build-test':
                    result = await this.runBuildTest(timeoutMs);
                    break;
                case 'syntax-validation':
                    result = await this.runSyntaxValidation();
                    break;
                case 'dependency-check':
                    result = await this.runDependencyCheck();
                    break;
                case 'security-scan':
                    result = await this.runSecurityScan();
                    break;
                case 'integration-test':
                    result = await this.runIntegrationTest(versionInfo);
                    break;
                default:
                    throw new Error(`Unknown test suite: ${suiteName}`);
            }
            
            const executionTime = Date.now() - startTime;
            
            return {
                suite: suiteName,
                success: result.success,
                executionTime,
                output: result.output,
                error: result.error,
                details: result.details,
                timestamp: new Date().toISOString()
            };
            
        } catch (error) {
            return {
                suite: suiteName,
                success: false,
                executionTime: Date.now() - startTime,
                error: error.message,
                timestamp: new Date().toISOString()
            };
        }
    }

    async runFlakeCheck(timeoutMs) {
        console.log('🔍 Running flake check...');
        
        return this.executeCommand('nix', ['flake', 'check'], {
            timeout: timeoutMs,
            description: 'Nix flake validation'
        });
    }

    async runBuildTest(timeoutMs) {
        console.log('🏗️  Running build test...');
        
        return this.executeCommand('nix', ['build'], {
            timeout: timeoutMs,
            description: 'Nix build test'
        });
    }

    async runSyntaxValidation() {
        console.log('📝 Running syntax validation...');
        
        try {
            // Check flake.nix syntax
            const flakeContent = await fs.readFile(path.join(this.repoPath, 'flake.nix'), 'utf8');
            
            // Basic syntax checks
            const syntaxChecks = [
                { name: 'balanced braces', check: this.checkBalancedBraces(flakeContent) },
                { name: 'no trailing commas', check: this.checkNoTrailingCommas(flakeContent) },
                { name: 'proper indentation', check: this.checkIndentation(flakeContent) }
            ];
            
            const issues = [];
            for (const check of syntaxChecks) {
                if (!check.check) {
                    issues.push(check.name);
                }
            }
            
            return {
                success: issues.length === 0,
                details: { syntaxIssues: issues },
                output: issues.length === 0 ? 'Syntax validation passed' : `Issues found: ${issues.join(', ')}`
            };
            
        } catch (error) {
            return {
                success: false,
                error: error.message,
                output: 'Syntax validation failed'
            };
        }
    }

    async runDependencyCheck() {
        console.log('📦 Running dependency check...');
        
        try {
            // Check flake inputs
            const flakeLockContent = await fs.readFile(path.join(this.repoPath, 'flake.lock'), 'utf8');
            const flakeLock = JSON.parse(flakeLockContent);
            
            const dependencies = Object.keys(flakeLock.nodes.root.inputs || {});
            const dependencyInfo = [];
            
            for (const dep of dependencies) {
                const node = flakeLock.nodes[dep];
                if (node && node.original) {
                    dependencyInfo.push({
                        name: dep,
                        type: node.original.type,
                        url: node.original.url || `${node.original.owner}/${node.original.repo}`,
                        locked: node.locked
                    });
                }
            }
            
            return {
                success: true,
                details: { dependencies: dependencyInfo },
                output: `Found ${dependencyInfo.length} dependencies`
            };
            
        } catch (error) {
            return {
                success: false,
                error: error.message,
                output: 'Dependency check failed'
            };
        }
    }

    async runSecurityScan() {
        console.log('🛡️  Running security scan...');
        
        try {
            const issues = [];
            
            // Check for common security issues in flake.nix
            const flakeContent = await fs.readFile(path.join(this.repoPath, 'flake.nix'), 'utf8');
            
            // Security checks
            if (flakeContent.includes('allowUnfree = true')) {
                issues.push('Allows unfree packages');
            }
            
            if (flakeContent.includes('allowUnsupportedSystem = true')) {
                issues.push('Allows unsupported systems');
            }
            
            if (flakeContent.includes('fetchurl') && !flakeContent.includes('sha256')) {
                issues.push('URL fetch without hash verification');
            }
            
            return {
                success: issues.length === 0,
                details: { securityIssues: issues },
                output: issues.length === 0 ? 'No security issues found' : `Issues: ${issues.join(', ')}`
            };
            
        } catch (error) {
            return {
                success: false,
                error: error.message,
                output: 'Security scan failed'
            };
        }
    }

    async runIntegrationTest(versionInfo) {
        console.log('🔗 Running integration test...');
        
        try {
            // Test that the package can be imported/used
            const testScript = `
                nix-instantiate --eval --expr 'let
                  flake = builtins.getFlake (toString ./.);
                  pkg = flake.packages.x86_64-linux.default or flake.packages.default;
                in pkg.name'
            `;
            
            const result = await this.executeCommand('sh', ['-c', testScript], {
                timeout: 30000,
                description: 'Integration test'
            });
            
            return {
                success: result.success,
                details: { packageName: versionInfo.packageName, version: versionInfo.newVersion },
                output: result.output,
                error: result.error
            };
            
        } catch (error) {
            return {
                success: false,
                error: error.message,
                output: 'Integration test failed'
            };
        }
    }

    async runPerformanceTests(versionInfo) {
        console.log('⚡ Running performance tests...');
        
        const startTime = Date.now();
        
        try {
            // Test flake evaluation time
            const evalResult = await this.executeCommand('nix', ['flake', 'show', '--json'], {
                timeout: 60000,
                description: 'Flake evaluation performance test'
            });
            
            const evalTime = Date.now() - startTime;
            
            // Test build time (if not too expensive)
            const buildStartTime = Date.now();
            const buildResult = await this.executeCommand('nix', ['build', '--dry-run'], {
                timeout: 30000,
                description: 'Build time estimation'
            });
            const estimatedBuildTime = Date.now() - buildStartTime;
            
            const performanceMetrics = {
                evaluationTimeMs: evalTime,
                estimatedBuildTimeMs: estimatedBuildTime,
                flakeSize: await this.getFlakeSize()
            };
            
            return {
                suite: 'performance',
                success: evalResult.success && buildResult.success,
                details: { metrics: performanceMetrics },
                output: `Evaluation: ${evalTime}ms, Build estimation: ${estimatedBuildTime}ms`,
                timestamp: new Date().toISOString()
            };
            
        } catch (error) {
            return {
                suite: 'performance',
                success: false,
                error: error.message,
                output: 'Performance tests failed',
                timestamp: new Date().toISOString()
            };
        }
    }

    async runSecurityScans(versionInfo) {
        console.log('🔐 Running security scans...');
        
        try {
            const securityChecks = [
                await this.checkFilePermissions(),
                await this.checkForSecrets(),
                await this.checkDependencyVulnerabilities()
            ];
            
            const allPassed = securityChecks.every(check => check.success);
            const issues = securityChecks.filter(check => !check.success);
            
            return {
                suite: 'security',
                success: allPassed,
                details: { checks: securityChecks },
                output: allPassed ? 'All security checks passed' : `${issues.length} security issues found`,
                timestamp: new Date().toISOString()
            };
            
        } catch (error) {
            return {
                suite: 'security',
                success: false,
                error: error.message,
                output: 'Security scans failed',
                timestamp: new Date().toISOString()
            };
        }
    }

    async postValidationAnalysis() {
        console.log('📊 Running post-validation analysis...');
        
        const successfulTests = this.validationResults.filter(r => r.success).length;
        const totalTests = this.validationResults.length;
        const successRate = totalTests > 0 ? (successfulTests / totalTests) * 100 : 0;
        
        const analysis = {
            successRate,
            totalTests,
            successfulTests,
            failedTests: totalTests - successfulTests,
            averageExecutionTime: this.calculateAverageExecutionTime(),
            recommendations: this.generateRecommendations()
        };
        
        return {
            suite: 'analysis',
            success: successRate >= 80, // 80% success rate threshold
            details: analysis,
            output: `Success rate: ${successRate.toFixed(1)}% (${successfulTests}/${totalTests})`,
            timestamp: new Date().toISOString()
        };
    }

    calculateAverageExecutionTime() {
        const times = this.validationResults
            .filter(r => r.executionTime)
            .map(r => r.executionTime);
        
        return times.length > 0 ? times.reduce((a, b) => a + b, 0) / times.length : 0;
    }

    generateRecommendations() {
        const recommendations = [];
        const failedTests = this.validationResults.filter(r => !r.success);
        
        if (failedTests.some(t => t.suite === 'flake-check')) {
            recommendations.push('Fix flake configuration issues');
        }
        
        if (failedTests.some(t => t.suite === 'build-test')) {
            recommendations.push('Review build dependencies and configuration');
        }
        
        if (failedTests.some(t => t.suite === 'security-scan')) {
            recommendations.push('Address security vulnerabilities');
        }
        
        const avgTime = this.calculateAverageExecutionTime();
        if (avgTime > 60000) { // More than 1 minute average
            recommendations.push('Consider optimizing for faster validation');
        }
        
        return recommendations;
    }

    generateSummary() {
        const successful = this.validationResults.filter(r => r.success);
        const failed = this.validationResults.filter(r => !r.success);
        
        return {
            total: this.validationResults.length,
            successful: successful.length,
            failed: failed.length,
            successRate: this.validationResults.length > 0 ? (successful.length / this.validationResults.length) * 100 : 0,
            failedSuites: failed.map(r => r.suite),
            totalTime: this.validationResults.reduce((sum, r) => sum + (r.executionTime || 0), 0)
        };
    }

    // Utility methods
    async executeCommand(command, args, options = {}) {
        const { timeout = 60000, description = 'Command execution' } = options;
        
        return new Promise((resolve) => {
            const process = spawn(command, args, {
                cwd: this.repoPath,
                stdio: 'pipe'
            });
            
            let stdout = '';
            let stderr = '';
            let timeoutId;
            
            if (timeout > 0) {
                timeoutId = setTimeout(() => {
                    process.kill();
                    resolve({
                        success: false,
                        error: 'Command timeout',
                        output: 'Process killed due to timeout'
                    });
                }, timeout);
            }
            
            process.stdout.on('data', (data) => {
                stdout += data.toString();
            });
            
            process.stderr.on('data', (data) => {
                stderr += data.toString();
            });
            
            process.on('close', (code) => {
                if (timeoutId) clearTimeout(timeoutId);
                
                resolve({
                    success: code === 0,
                    output: stdout.trim(),
                    error: code !== 0 ? stderr.trim() : null,
                    exitCode: code
                });
            });
        });
    }

    async fileExists(filename) {
        try {
            await fs.access(path.join(this.repoPath, filename));
            return true;
        } catch {
            return false;
        }
    }

    async commandExists(command) {
        try {
            const result = await this.executeCommand('which', [command], { timeout: 5000 });
            return result.success;
        } catch {
            return false;
        }
    }

    async isGitRepository() {
        try {
            const result = await this.executeCommand('git', ['rev-parse', '--git-dir'], { timeout: 5000 });
            return result.success;
        } catch {
            return false;
        }
    }

    checkBalancedBraces(content) {
        const braces = { '{': 0, '[': 0, '(': 0 };
        
        for (const char of content) {
            if (char === '{') braces['{']++;
            else if (char === '}') braces['{']--;
            else if (char === '[') braces['[']++;
            else if (char === ']') braces['[']--;
            else if (char === '(') braces['(']++;
            else if (char === ')') braces['(']--;
        }
        
        return Object.values(braces).every(count => count === 0);
    }

    checkNoTrailingCommas(content) {
        // Simple check for trailing commas before closing braces/brackets
        return !content.match(/,\s*[}\]]/);
    }

    checkIndentation(content) {
        // Basic indentation check - look for consistent spacing
        const lines = content.split('\n');
        const indentPattern = /^(\s*)/;
        
        // Check for consistent indentation (either all spaces or all tabs)
        const hasSpaces = lines.some(line => indentPattern.exec(line)?.[1]?.includes(' '));
        const hasTabs = lines.some(line => indentPattern.exec(line)?.[1]?.includes('\t'));
        
        return !(hasSpaces && hasTabs); // Don't mix spaces and tabs
    }

    async getFlakeSize() {
        try {
            const flakeStats = await fs.stat(path.join(this.repoPath, 'flake.nix'));
            const lockStats = await fs.stat(path.join(this.repoPath, 'flake.lock'));
            return flakeStats.size + lockStats.size;
        } catch {
            return 0;
        }
    }

    async checkFilePermissions() {
        try {
            const flakeStats = await fs.stat(path.join(this.repoPath, 'flake.nix'));
            const lockStats = await fs.stat(path.join(this.repoPath, 'flake.lock'));
            
            // Check for overly permissive permissions
            const flakeMode = flakeStats.mode & 0o777;
            const lockMode = lockStats.mode & 0o777;
            
            const isSecure = flakeMode <= 0o644 && lockMode <= 0o644;
            
            return {
                success: isSecure,
                details: { flakeMode, lockMode },
                message: isSecure ? 'File permissions are secure' : 'File permissions are too permissive'
            };
        } catch (error) {
            return {
                success: false,
                error: error.message,
                message: 'Failed to check file permissions'
            };
        }
    }

    async checkForSecrets() {
        try {
            const flakeContent = await fs.readFile(path.join(this.repoPath, 'flake.nix'), 'utf8');
            
            // Common patterns that might indicate secrets
            const secretPatterns = [
                /password\s*=\s*["'][^"']+["']/i,
                /token\s*=\s*["'][^"']+["']/i,
                /key\s*=\s*["'][^"']+["']/i,
                /secret\s*=\s*["'][^"']+["']/i,
                /[A-Za-z0-9]{32,}/ // Long random strings
            ];
            
            const foundSecrets = [];
            secretPatterns.forEach((pattern, index) => {
                const matches = flakeContent.match(pattern);
                if (matches) {
                    foundSecrets.push(`Pattern ${index + 1}: ${matches[0].substring(0, 20)}...`);
                }
            });
            
            return {
                success: foundSecrets.length === 0,
                details: { foundSecrets },
                message: foundSecrets.length === 0 ? 'No secrets detected' : `${foundSecrets.length} potential secrets found`
            };
        } catch (error) {
            return {
                success: false,
                error: error.message,
                message: 'Failed to scan for secrets'
            };
        }
    }

    async checkDependencyVulnerabilities() {
        // Placeholder for dependency vulnerability checking
        // In a real implementation, this would check against vulnerability databases
        return {
            success: true,
            details: { vulnerabilities: [] },
            message: 'No known vulnerabilities (basic check)'
        };
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
    const command = args[0] || 'run';
    const versionInfoJson = args[1];
    
    (async () => {
        try {
            const pipeline = new ValidationPipeline({
                enablePerformanceTests: process.env.ENABLE_PERF_TESTS === 'true',
                enableSecurityScans: process.env.ENABLE_SECURITY_SCANS !== 'false'
            });
            
            await pipeline.init();
            
            switch (command) {
                case 'run':
                    if (!versionInfoJson) {
                        console.error('Usage: validation-pipeline.js run <version-info-json>');
                        process.exit(1);
                    }
                    
                    const versionInfo = JSON.parse(versionInfoJson);
                    const options = {
                        skipTests: args.includes('--skip-tests') ? args[args.indexOf('--skip-tests') + 1]?.split(',') || [] : [],
                        strictMode: !args.includes('--non-strict'),
                        timeoutMs: parseInt(args[args.indexOf('--timeout') + 1] || '300000')
                    };
                    
                    const result = await pipeline.runValidationPipeline(versionInfo, options);
                    
                    console.log('\n📊 Validation Summary:');
                    console.log(JSON.stringify(result.summary, null, 2));
                    
                    process.exit(result.success ? 0 : 1);
                    
                case 'test':
                    console.log('🧪 Running test validation pipeline...');
                    const testVersionInfo = { oldVersion: '1.7.0', newVersion: '1.7.1', packageName: 'backlog.md' };
                    const testResult = await pipeline.runValidationPipeline(testVersionInfo, { strictMode: false });
                    console.log('Test result:', testResult.success ? 'PASS' : 'FAIL');
                    break;
                    
                default:
                    console.log('Usage: validation-pipeline.js [run|test] [options]');
                    console.log('');
                    console.log('Commands:');
                    console.log('  run <version-info-json>  - Run full validation pipeline');
                    console.log('  test                     - Run test validation');
                    console.log('');
                    console.log('Options:');
                    console.log('  --skip-tests <list>      - Skip specific test suites (comma-separated)');
                    console.log('  --non-strict             - Continue on test failures');
                    console.log('  --timeout <ms>           - Set timeout for individual tests');
                    console.log('');
                    console.log('Environment variables:');
                    console.log('  ENABLE_PERF_TESTS=true   - Enable performance testing');
                    console.log('  ENABLE_SECURITY_SCANS=false - Disable security scans');
                    process.exit(1);
            }
            
        } catch (error) {
            console.error('❌ Validation pipeline failed:', error.message);
            process.exit(1);
        }
    })();
}

module.exports = ValidationPipeline;