#!/usr/bin/env node
/**
 * Automated Flake Lock Update Mechanism
 * Updates flake.lock when NPM package versions change
 */

const fs = require('fs').promises;
const path = require('path');
const { spawn, exec } = require('child_process');
const crypto = require('crypto');

class FlakeUpdater {
    constructor(config = {}) {
        this.flakeFile = config.flakeFile || path.join(process.cwd(), 'flake.nix');
        this.flakeLockFile = config.flakeLockFile || path.join(process.cwd(), 'flake.lock');
        this.packageName = config.packageName || 'backlog.md';
        this.memoryNamespace = 'hive/auto-update';
        this.backupDir = path.join(process.cwd(), 'src/auto-updater/backups');
    }

    async init() {
        console.log('🔧 Initializing Flake Updater');
        await fs.mkdir(this.backupDir, { recursive: true });
        await this.storeMemory('flake_updater_init', {
            flakeFile: this.flakeFile,
            flakeLockFile: this.flakeLockFile,
            timestamp: new Date().toISOString()
        });
    }

    async createBackup() {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const backupPath = path.join(this.backupDir, `flake-backup-${timestamp}`);
        
        try {
            console.log('💾 Creating backup...');
            
            // Backup flake.nix and flake.lock
            const flakeContent = await fs.readFile(this.flakeFile, 'utf8');
            const flakeLockContent = await fs.readFile(this.flakeLockFile, 'utf8');
            
            await fs.mkdir(backupPath, { recursive: true });
            await fs.writeFile(path.join(backupPath, 'flake.nix'), flakeContent);
            await fs.writeFile(path.join(backupPath, 'flake.lock'), flakeLockContent);
            
            // Create backup metadata
            const metadata = {
                timestamp,
                flakeFile: this.flakeFile,
                flakeLockFile: this.flakeLockFile,
                packageName: this.packageName,
                backupPath,
                checksums: {
                    'flake.nix': this.calculateChecksum(flakeContent),
                    'flake.lock': this.calculateChecksum(flakeLockContent)
                }
            };
            
            await fs.writeFile(
                path.join(backupPath, 'metadata.json'),
                JSON.stringify(metadata, null, 2)
            );
            
            console.log(`✅ Backup created: ${backupPath}`);
            await this.storeMemory('backup_created', metadata);
            
            return backupPath;
            
        } catch (error) {
            console.error('❌ Backup creation failed:', error.message);
            throw error;
        }
    }

    calculateChecksum(content) {
        return crypto.createHash('sha256').update(content).digest('hex');
    }

    async updateFlakeNix(versionInfo) {
        console.log('📝 Updating flake.nix with new version...');
        
        try {
            let flakeContent = await fs.readFile(this.flakeFile, 'utf8');
            
            // Update the version in buildGoModule or similar
            const versionRegex = /version = "[^"]+"/;
            if (versionRegex.test(flakeContent)) {
                flakeContent = flakeContent.replace(
                    versionRegex,
                    `version = "${versionInfo.newVersion}"`
                );
            }
            
            // Update package description if present
            const descRegex = /description = "[^"]*backlog\.md[^"]*"/i;
            if (descRegex.test(flakeContent)) {
                flakeContent = flakeContent.replace(
                    descRegex,
                    `description = "backlog.md ${versionInfo.newVersion} - Markdown-native Task Manager"`
                );
            }
            
            // Add integrity hash if present
            if (versionInfo.integrity) {
                const integrityRegex = /integrity = "[^"]+"/;
                if (integrityRegex.test(flakeContent)) {
                    flakeContent = flakeContent.replace(
                        integrityRegex,
                        `integrity = "${versionInfo.integrity}"`
                    );
                }
            }
            
            await fs.writeFile(this.flakeFile, flakeContent);
            console.log('✅ flake.nix updated');
            
            await this.storeMemory('flake_nix_updated', {
                oldVersion: versionInfo.oldVersion,
                newVersion: versionInfo.newVersion,
                timestamp: new Date().toISOString()
            });
            
        } catch (error) {
            console.error('❌ Failed to update flake.nix:', error.message);
            throw error;
        }
    }

    async updateFlakeLock() {
        console.log('🔐 Updating flake.lock...');
        
        return new Promise((resolve, reject) => {
            const nixCommand = spawn('nix', ['flake', 'update'], {
                cwd: process.cwd(),
                stdio: 'pipe'
            });
            
            let output = '';
            let errorOutput = '';
            
            nixCommand.stdout.on('data', (data) => {
                output += data.toString();
                process.stdout.write(data);
            });
            
            nixCommand.stderr.on('data', (data) => {
                errorOutput += data.toString();
                process.stderr.write(data);
            });
            
            nixCommand.on('close', async (code) => {
                if (code === 0) {
                    console.log('✅ flake.lock updated successfully');
                    await this.storeMemory('flake_lock_updated', {
                        output,
                        timestamp: new Date().toISOString()
                    });
                    resolve();
                } else {
                    const error = new Error(`nix flake update failed with code ${code}: ${errorOutput}`);
                    await this.storeMemory('flake_lock_update_failed', {
                        code,
                        output,
                        errorOutput,
                        timestamp: new Date().toISOString()
                    });
                    reject(error);
                }
            });
        });
    }

    async validateUpdate() {
        console.log('🔍 Validating update...');
        
        return new Promise((resolve, reject) => {
            const nixCommand = spawn('nix', ['flake', 'check'], {
                cwd: process.cwd(),
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
                
                await this.storeMemory('update_validation', {
                    isValid,
                    code,
                    output,
                    errorOutput,
                    timestamp: new Date().toISOString()
                });
                
                if (isValid) {
                    console.log('✅ Update validation successful');
                    resolve(true);
                } else {
                    console.error('❌ Update validation failed');
                    resolve(false);
                }
            });
        });
    }

    async testBuild() {
        console.log('🧪 Testing build...');
        
        return new Promise((resolve, reject) => {
            const nixCommand = spawn('nix', ['build'], {
                cwd: process.cwd(),
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
                
                await this.storeMemory('build_test', {
                    buildSuccess,
                    code,
                    output,
                    errorOutput,
                    timestamp: new Date().toISOString()
                });
                
                if (buildSuccess) {
                    console.log('✅ Build test successful');
                    resolve(true);
                } else {
                    console.error('❌ Build test failed');
                    resolve(false);
                }
            });
        });
    }

    async rollback(backupPath) {
        console.log('⏪ Rolling back to backup...');
        
        try {
            const flakeBackup = path.join(backupPath, 'flake.nix');
            const flakeLockBackup = path.join(backupPath, 'flake.lock');
            
            await fs.copyFile(flakeBackup, this.flakeFile);
            await fs.copyFile(flakeLockBackup, this.flakeLockFile);
            
            console.log('✅ Rollback completed');
            await this.storeMemory('rollback_completed', {
                backupPath,
                timestamp: new Date().toISOString()
            });
            
        } catch (error) {
            console.error('❌ Rollback failed:', error.message);
            await this.storeMemory('rollback_failed', {
                backupPath,
                error: error.message,
                timestamp: new Date().toISOString()
            });
            throw error;
        }
    }

    async performUpdate(versionInfo) {
        console.log(`🚀 Starting flake update: ${versionInfo.oldVersion} → ${versionInfo.newVersion}`);
        
        let backupPath = null;
        
        try {
            // Step 1: Create backup
            backupPath = await this.createBackup();
            
            // Step 2: Update flake.nix
            await this.updateFlakeNix(versionInfo);
            
            // Step 3: Update flake.lock
            await this.updateFlakeLock();
            
            // Step 4: Validate the update
            const isValid = await this.validateUpdate();
            if (!isValid) {
                throw new Error('Update validation failed');
            }
            
            // Step 5: Test build
            const buildSuccess = await this.testBuild();
            if (!buildSuccess) {
                throw new Error('Build test failed');
            }
            
            console.log('🎉 Flake update completed successfully!');
            
            await this.storeMemory('update_completed', {
                versionInfo,
                backupPath,
                timestamp: new Date().toISOString()
            });
            
            return true;
            
        } catch (error) {
            console.error('❌ Update failed:', error.message);
            
            if (backupPath) {
                console.log('🔄 Attempting rollback...');
                try {
                    await this.rollback(backupPath);
                } catch (rollbackError) {
                    console.error('❌ Rollback also failed:', rollbackError.message);
                }
            }
            
            await this.storeMemory('update_failed', {
                versionInfo,
                error: error.message,
                backupPath,
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
    const versionInfoJson = args[0];
    
    if (!versionInfoJson) {
        console.error('Usage: flake-updater.js <version-info-json>');
        process.exit(1);
    }
    
    (async () => {
        try {
            const versionInfo = JSON.parse(versionInfoJson);
            const updater = new FlakeUpdater();
            
            await updater.init();
            await updater.performUpdate(versionInfo);
            
            console.log('✅ Update process completed');
            
        } catch (error) {
            console.error('❌ Update process failed:', error.message);
            process.exit(1);
        }
    })();
}

module.exports = FlakeUpdater;