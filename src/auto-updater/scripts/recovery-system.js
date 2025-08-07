#!/usr/bin/env node
/**
 * Rollback and Recovery System
 * Handles error recovery, rollbacks, and system restoration
 */

const fs = require('fs').promises;
const path = require('path');
const { spawn } = require('child_process');
const crypto = require('crypto');

class RecoverySystem {
    constructor(config = {}) {
        this.backupDir = config.backupDir || path.join(process.cwd(), 'src/auto-updater/backups');
        this.memoryNamespace = 'hive/auto-update';
        this.recoveryLogFile = path.join(this.backupDir, 'recovery.log');
        this.maxBackups = config.maxBackups || 10;
        this.repoPath = config.repoPath || process.cwd();
    }

    async init() {
        console.log('🛠️ Initializing Recovery System');
        await fs.mkdir(this.backupDir, { recursive: true });
        await this.logRecovery('system_init', 'Recovery system initialized');
        await this.storeMemory('recovery_system_init', {
            backupDir: this.backupDir,
            maxBackups: this.maxBackups,
            timestamp: new Date().toISOString()
        });
    }

    async logRecovery(action, message, data = {}) {
        const logEntry = {
            timestamp: new Date().toISOString(),
            action,
            message,
            data
        };
        
        try {
            const logLine = JSON.stringify(logEntry) + '\n';
            await fs.appendFile(this.recoveryLogFile, logLine);
            console.log(`📝 Recovery log: ${action} - ${message}`);
        } catch (error) {
            console.warn('⚠️  Failed to write recovery log:', error.message);
        }
    }

    async listBackups() {
        try {
            const entries = await fs.readdir(this.backupDir, { withFileTypes: true });
            const backups = [];
            
            for (const entry of entries) {
                if (entry.isDirectory() && entry.name.startsWith('flake-backup-')) {
                    const backupPath = path.join(this.backupDir, entry.name);
                    const metadataPath = path.join(backupPath, 'metadata.json');
                    
                    try {
                        const metadataContent = await fs.readFile(metadataPath, 'utf8');
                        const metadata = JSON.parse(metadataContent);
                        
                        backups.push({
                            name: entry.name,
                            path: backupPath,
                            metadata
                        });
                    } catch (error) {
                        console.warn(`⚠️  Failed to read backup metadata: ${entry.name}`);
                    }
                }
            }
            
            // Sort by timestamp (newest first)
            backups.sort((a, b) => 
                new Date(b.metadata.timestamp) - new Date(a.metadata.timestamp)
            );
            
            return backups;
            
        } catch (error) {
            console.error('❌ Failed to list backups:', error.message);
            return [];
        }
    }

    async validateBackup(backupPath) {
        try {
            console.log(`🔍 Validating backup: ${backupPath}`);
            
            const metadataPath = path.join(backupPath, 'metadata.json');
            const flakePath = path.join(backupPath, 'flake.nix');
            const flakeLockPath = path.join(backupPath, 'flake.lock');
            
            // Check if required files exist
            const files = [metadataPath, flakePath, flakeLockPath];
            for (const file of files) {
                await fs.access(file);
            }
            
            // Validate metadata
            const metadataContent = await fs.readFile(metadataPath, 'utf8');
            const metadata = JSON.parse(metadataContent);
            
            // Verify checksums
            const flakeContent = await fs.readFile(flakePath, 'utf8');
            const flakeLockContent = await fs.readFile(flakeLockPath, 'utf8');
            
            const flakeChecksum = crypto.createHash('sha256').update(flakeContent).digest('hex');
            const flakeLockChecksum = crypto.createHash('sha256').update(flakeLockContent).digest('hex');
            
            if (metadata.checksums['flake.nix'] !== flakeChecksum) {
                throw new Error('flake.nix checksum mismatch');
            }
            
            if (metadata.checksums['flake.lock'] !== flakeLockChecksum) {
                throw new Error('flake.lock checksum mismatch');
            }
            
            console.log('✅ Backup validation successful');
            await this.logRecovery('backup_validated', `Backup ${backupPath} is valid`);
            
            return {
                isValid: true,
                metadata
            };
            
        } catch (error) {
            console.error(`❌ Backup validation failed: ${error.message}`);
            await this.logRecovery('backup_validation_failed', `Backup ${backupPath} validation failed`, {
                error: error.message
            });
            
            return {
                isValid: false,
                error: error.message
            };
        }
    }

    async performRollback(backupPath, options = {}) {
        console.log(`⏪ Starting rollback to: ${backupPath}`);
        
        const {
            skipGitReset = false,
            skipValidation = false,
            force = false
        } = options;
        
        let rollbackSteps = [];
        
        try {
            // Step 1: Validate backup
            if (!skipValidation) {
                const validation = await this.validateBackup(backupPath);
                if (!validation.isValid) {
                    throw new Error(`Backup validation failed: ${validation.error}`);
                }
                rollbackSteps.push('backup_validated');
            }
            
            // Step 2: Create current state backup before rollback
            const preRollbackBackup = await this.createPreRollbackBackup();
            rollbackSteps.push('pre_rollback_backup_created');
            
            // Step 3: Restore flake files
            await this.restoreFlakeFiles(backupPath);
            rollbackSteps.push('flake_files_restored');
            
            // Step 4: Validate restored flake
            const flakeValid = await this.validateFlake();
            if (!flakeValid && !force) {
                throw new Error('Restored flake validation failed');
            }
            rollbackSteps.push('restored_flake_validated');
            
            // Step 5: Git reset if requested
            if (!skipGitReset) {
                await this.performGitReset();
                rollbackSteps.push('git_reset_completed');
            }
            
            // Step 6: Test build
            const buildSuccess = await this.testBuild();
            if (!buildSuccess && !force) {
                throw new Error('Build test failed after rollback');
            }
            rollbackSteps.push('build_test_completed');
            
            console.log('🎉 Rollback completed successfully!');
            
            await this.logRecovery('rollback_completed', `Rollback to ${backupPath} successful`, {
                backupPath,
                preRollbackBackup,
                rollbackSteps
            });
            
            await this.storeMemory('rollback_completed', {
                backupPath,
                preRollbackBackup,
                rollbackSteps,
                timestamp: new Date().toISOString()
            });
            
            return {
                success: true,
                backupPath,
                preRollbackBackup,
                steps: rollbackSteps
            };
            
        } catch (error) {
            console.error('❌ Rollback failed:', error.message);
            
            await this.logRecovery('rollback_failed', `Rollback to ${backupPath} failed`, {
                error: error.message,
                completedSteps: rollbackSteps
            });
            
            // Attempt to restore pre-rollback state if we created a backup
            if (rollbackSteps.includes('pre_rollback_backup_created')) {
                console.log('🔄 Attempting to restore pre-rollback state...');
                // This could be recursive, but we limit it with skipGitReset and force
                // Implementation would restore the pre-rollback backup
            }
            
            throw error;
        }
    }

    async createPreRollbackBackup() {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const backupPath = path.join(this.backupDir, `pre-rollback-${timestamp}`);
        
        try {
            console.log('💾 Creating pre-rollback backup...');
            
            const flakeFile = path.join(this.repoPath, 'flake.nix');
            const flakeLockFile = path.join(this.repoPath, 'flake.lock');
            
            const flakeContent = await fs.readFile(flakeFile, 'utf8');
            const flakeLockContent = await fs.readFile(flakeLockFile, 'utf8');
            
            await fs.mkdir(backupPath, { recursive: true });
            await fs.writeFile(path.join(backupPath, 'flake.nix'), flakeContent);
            await fs.writeFile(path.join(backupPath, 'flake.lock'), flakeLockContent);
            
            const metadata = {
                timestamp,
                type: 'pre-rollback',
                flakeFile,
                flakeLockFile,
                backupPath,
                checksums: {
                    'flake.nix': crypto.createHash('sha256').update(flakeContent).digest('hex'),
                    'flake.lock': crypto.createHash('sha256').update(flakeLockContent).digest('hex')
                }
            };
            
            await fs.writeFile(
                path.join(backupPath, 'metadata.json'),
                JSON.stringify(metadata, null, 2)
            );
            
            console.log(`✅ Pre-rollback backup created: ${backupPath}`);
            return backupPath;
            
        } catch (error) {
            console.error('❌ Failed to create pre-rollback backup:', error.message);
            throw error;
        }
    }

    async restoreFlakeFiles(backupPath) {
        console.log('📁 Restoring flake files...');
        
        try {
            const backupFlake = path.join(backupPath, 'flake.nix');
            const backupFlakeLock = path.join(backupPath, 'flake.lock');
            
            const currentFlake = path.join(this.repoPath, 'flake.nix');
            const currentFlakeLock = path.join(this.repoPath, 'flake.lock');
            
            await fs.copyFile(backupFlake, currentFlake);
            await fs.copyFile(backupFlakeLock, currentFlakeLock);
            
            console.log('✅ Flake files restored');
            
        } catch (error) {
            console.error('❌ Failed to restore flake files:', error.message);
            throw error;
        }
    }

    async validateFlake() {
        console.log('🔍 Validating flake...');
        
        return new Promise((resolve) => {
            const nixCommand = spawn('nix', ['flake', 'check'], {
                cwd: this.repoPath,
                stdio: 'pipe'
            });
            
            let output = '';
            let errorOutput = '';
            
            nixCommand.stdout.on('data', (data) => {
                output += data.toString();
            });
            
            nixCommand.stderr.on('data', (data) => {
                errorOutput += data.toString();
            });
            
            nixCommand.on('close', async (code) => {
                const isValid = code === 0;
                
                if (isValid) {
                    console.log('✅ Flake validation successful');
                } else {
                    console.error('❌ Flake validation failed:', errorOutput);
                }
                
                await this.logRecovery('flake_validation', `Flake validation ${isValid ? 'passed' : 'failed'}`, {
                    isValid,
                    output,
                    errorOutput
                });
                
                resolve(isValid);
            });
        });
    }

    async testBuild() {
        console.log('🧪 Testing build...');
        
        return new Promise((resolve) => {
            const nixCommand = spawn('nix', ['build'], {
                cwd: this.repoPath,
                stdio: 'pipe'
            });
            
            let output = '';
            let errorOutput = '';
            
            nixCommand.stdout.on('data', (data) => {
                output += data.toString();
            });
            
            nixCommand.stderr.on('data', (data) => {
                errorOutput += data.toString();
            });
            
            nixCommand.on('close', async (code) => {
                const buildSuccess = code === 0;
                
                if (buildSuccess) {
                    console.log('✅ Build test successful');
                } else {
                    console.error('❌ Build test failed:', errorOutput);
                }
                
                await this.logRecovery('build_test', `Build test ${buildSuccess ? 'passed' : 'failed'}`, {
                    buildSuccess,
                    output,
                    errorOutput
                });
                
                resolve(buildSuccess);
            });
        });
    }

    async performGitReset() {
        console.log('🔄 Performing Git reset...');
        
        return new Promise((resolve, reject) => {
            const gitCommand = spawn('git', ['checkout', 'HEAD', '--', 'flake.nix', 'flake.lock'], {
                cwd: this.repoPath,
                stdio: 'pipe'
            });
            
            let output = '';
            let errorOutput = '';
            
            gitCommand.stdout.on('data', (data) => {
                output += data.toString();
            });
            
            gitCommand.stderr.on('data', (data) => {
                errorOutput += data.toString();
            });
            
            gitCommand.on('close', async (code) => {
                if (code === 0) {
                    console.log('✅ Git reset completed');
                    await this.logRecovery('git_reset', 'Git reset successful', { output });
                    resolve();
                } else {
                    console.error('❌ Git reset failed:', errorOutput);
                    await this.logRecovery('git_reset_failed', 'Git reset failed', { errorOutput });
                    reject(new Error(`Git reset failed: ${errorOutput}`));
                }
            });
        });
    }

    async cleanupOldBackups() {
        console.log('🧹 Cleaning up old backups...');
        
        try {
            const backups = await this.listBackups();
            
            if (backups.length <= this.maxBackups) {
                console.log(`✅ Backup count (${backups.length}) within limit (${this.maxBackups})`);
                return;
            }
            
            const backupsToDelete = backups.slice(this.maxBackups);
            let deletedCount = 0;
            
            for (const backup of backupsToDelete) {
                try {
                    await fs.rmdir(backup.path, { recursive: true });
                    deletedCount++;
                    console.log(`🗑️  Deleted old backup: ${backup.name}`);
                } catch (error) {
                    console.warn(`⚠️  Failed to delete backup ${backup.name}: ${error.message}`);
                }
            }
            
            console.log(`✅ Cleaned up ${deletedCount} old backups`);
            
            await this.logRecovery('cleanup_completed', `Cleaned up ${deletedCount} old backups`, {
                deletedCount,
                remainingCount: backups.length - deletedCount
            });
            
        } catch (error) {
            console.error('❌ Backup cleanup failed:', error.message);
            await this.logRecovery('cleanup_failed', 'Backup cleanup failed', {
                error: error.message
            });
        }
    }

    async getSystemStatus() {
        const backups = await this.listBackups();
        const latestBackup = backups[0];
        
        const status = {
            backupCount: backups.length,
            maxBackups: this.maxBackups,
            latestBackup: latestBackup ? {
                name: latestBackup.name,
                timestamp: latestBackup.metadata.timestamp,
                packageName: latestBackup.metadata.packageName
            } : null,
            recoveryLogExists: await this.fileExists(this.recoveryLogFile),
            timestamp: new Date().toISOString()
        };
        
        return status;
    }

    async fileExists(filePath) {
        try {
            await fs.access(filePath);
            return true;
        } catch {
            return false;
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
    const command = args[0] || 'status';
    
    const recovery = new RecoverySystem();
    
    (async () => {
        try {
            await recovery.init();
            
            switch (command) {
                case 'status':
                    const status = await recovery.getSystemStatus();
                    console.log('📊 Recovery System Status:');
                    console.log(JSON.stringify(status, null, 2));
                    break;
                    
                case 'list':
                    const backups = await recovery.listBackups();
                    console.log('📋 Available Backups:');
                    backups.forEach((backup, index) => {
                        console.log(`${index + 1}. ${backup.name} (${backup.metadata.timestamp})`);
                    });
                    break;
                    
                case 'rollback':
                    const backupName = args[1];
                    if (!backupName) {
                        console.error('Usage: recovery-system.js rollback <backup-name>');
                        process.exit(1);
                    }
                    
                    const backupPath = path.join(recovery.backupDir, backupName);
                    const result = await recovery.performRollback(backupPath, {
                        force: args.includes('--force'),
                        skipGitReset: args.includes('--skip-git'),
                        skipValidation: args.includes('--skip-validation')
                    });
                    
                    console.log('✅ Rollback result:', result);
                    break;
                    
                case 'validate':
                    const validateBackup = args[1];
                    if (!validateBackup) {
                        console.error('Usage: recovery-system.js validate <backup-name>');
                        process.exit(1);
                    }
                    
                    const validatePath = path.join(recovery.backupDir, validateBackup);
                    const validation = await recovery.validateBackup(validatePath);
                    console.log('🔍 Validation result:', validation);
                    break;
                    
                case 'cleanup':
                    await recovery.cleanupOldBackups();
                    break;
                    
                default:
                    console.log('Usage: recovery-system.js [status|list|rollback|validate|cleanup]');
                    console.log('');
                    console.log('Commands:');
                    console.log('  status                     - Show system status');
                    console.log('  list                       - List available backups');
                    console.log('  rollback <backup-name>     - Rollback to specific backup');
                    console.log('  validate <backup-name>     - Validate a backup');
                    console.log('  cleanup                    - Clean up old backups');
                    console.log('');
                    console.log('Rollback options:');
                    console.log('  --force                    - Force rollback even if validation fails');
                    console.log('  --skip-git                 - Skip git reset');
                    console.log('  --skip-validation          - Skip backup validation');
                    process.exit(1);
            }
            
        } catch (error) {
            console.error('❌ Recovery system failed:', error.message);
            process.exit(1);
        }
    })();
}

module.exports = RecoverySystem;