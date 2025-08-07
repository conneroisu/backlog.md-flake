#!/usr/bin/env node
/**
 * NPM Registry Version Monitoring Script
 * Monitors backlog.md package for version changes and triggers updates
 */

const fs = require('fs').promises;
const path = require('path');
const https = require('https');
const { spawn } = require('child_process');

class NpmVersionMonitor {
    constructor(config = {}) {
        this.packageName = config.packageName || 'backlog.md';
        this.currentVersion = config.currentVersion || '1.7.1';
        this.registryUrl = config.registryUrl || 'https://registry.npmjs.org';
        this.checkInterval = config.checkInterval || 300000; // 5 minutes
        this.configFile = config.configFile || path.join(__dirname, '../config/monitor.json');
        this.lockFile = config.lockFile || path.join(process.cwd(), 'flake.lock');
        this.memoryNamespace = 'hive/auto-update';
        this.isRunning = false;
    }

    async init() {
        console.log('🚀 Initializing NPM Version Monitor');
        await this.loadConfig();
        await this.storeMemory('monitor_init', {
            packageName: this.packageName,
            currentVersion: this.currentVersion,
            timestamp: new Date().toISOString()
        });
    }

    async loadConfig() {
        try {
            const configData = await fs.readFile(this.configFile, 'utf8');
            const config = JSON.parse(configData);
            Object.assign(this, config);
            console.log('📋 Configuration loaded');
        } catch (error) {
            console.log('⚙️  Creating default configuration');
            await this.saveConfig();
        }
    }

    async saveConfig() {
        const config = {
            packageName: this.packageName,
            currentVersion: this.currentVersion,
            registryUrl: this.registryUrl,
            checkInterval: this.checkInterval,
            lastCheck: new Date().toISOString(),
            lastUpdate: null
        };
        
        await fs.mkdir(path.dirname(this.configFile), { recursive: true });
        await fs.writeFile(this.configFile, JSON.stringify(config, null, 2));
    }

    async fetchPackageInfo() {
        return new Promise((resolve, reject) => {
            const url = `${this.registryUrl}/${this.packageName}`;
            
            https.get(url, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => {
                    try {
                        const packageInfo = JSON.parse(data);
                        resolve(packageInfo);
                    } catch (error) {
                        reject(new Error(`Failed to parse package info: ${error.message}`));
                    }
                });
            }).on('error', reject);
        });
    }

    async compareVersions(current, latest) {
        const parseVersion = (version) => {
            return version.split('.').map(num => parseInt(num, 10));
        };

        const currentParts = parseVersion(current);
        const latestParts = parseVersion(latest);

        for (let i = 0; i < Math.max(currentParts.length, latestParts.length); i++) {
            const currentPart = currentParts[i] || 0;
            const latestPart = latestParts[i] || 0;

            if (latestPart > currentPart) return 1;  // Update available
            if (latestPart < currentPart) return -1; // Downgrade (unusual)
        }

        return 0; // Same version
    }

    async detectVersionChange() {
        try {
            console.log('🔍 Checking for version updates...');
            const packageInfo = await this.fetchPackageInfo();
            const latestVersion = packageInfo['dist-tags'].latest;
            
            console.log(`📦 Current: ${this.currentVersion}, Latest: ${latestVersion}`);
            
            const comparison = await this.compareVersions(this.currentVersion, latestVersion);
            
            if (comparison > 0) {
                console.log(`🎉 New version available: ${latestVersion}`);
                
                const changeInfo = {
                    oldVersion: this.currentVersion,
                    newVersion: latestVersion,
                    publishedAt: packageInfo.time[latestVersion],
                    integrity: packageInfo.versions[latestVersion].dist.integrity,
                    shasum: packageInfo.versions[latestVersion].dist.shasum,
                    detectedAt: new Date().toISOString()
                };
                
                await this.storeMemory('version_change_detected', changeInfo);
                return changeInfo;
            }
            
            console.log('✅ No version changes detected');
            return null;
            
        } catch (error) {
            console.error('❌ Error checking version:', error.message);
            await this.storeMemory('version_check_error', {
                error: error.message,
                timestamp: new Date().toISOString()
            });
            throw error;
        }
    }

    async triggerUpdate(changeInfo) {
        console.log('🔄 Triggering flake update...');
        
        try {
            // Call the flake update mechanism
            const updateScript = path.join(__dirname, 'flake-updater.js');
            const updateProcess = spawn('node', [updateScript, JSON.stringify(changeInfo)], {
                stdio: 'inherit'
            });

            return new Promise((resolve, reject) => {
                updateProcess.on('close', (code) => {
                    if (code === 0) {
                        console.log('✅ Update triggered successfully');
                        resolve();
                    } else {
                        reject(new Error(`Update process failed with code ${code}`));
                    }
                });
            });
            
        } catch (error) {
            console.error('❌ Failed to trigger update:', error.message);
            await this.storeMemory('update_trigger_error', {
                error: error.message,
                changeInfo,
                timestamp: new Date().toISOString()
            });
            throw error;
        }
    }

    async startMonitoring() {
        if (this.isRunning) {
            console.log('⚠️  Monitor already running');
            return;
        }

        this.isRunning = true;
        console.log(`🎯 Starting version monitoring (interval: ${this.checkInterval}ms)`);
        
        const monitor = async () => {
            if (!this.isRunning) return;
            
            try {
                const changeInfo = await this.detectVersionChange();
                
                if (changeInfo) {
                    await this.triggerUpdate(changeInfo);
                    this.currentVersion = changeInfo.newVersion;
                    await this.saveConfig();
                }
                
            } catch (error) {
                console.error('❌ Monitor cycle failed:', error.message);
            }
            
            if (this.isRunning) {
                setTimeout(monitor, this.checkInterval);
            }
        };

        // Initial check
        await monitor();
    }

    async stopMonitoring() {
        console.log('🛑 Stopping version monitoring');
        this.isRunning = false;
        await this.storeMemory('monitor_stopped', {
            timestamp: new Date().toISOString()
        });
    }

    async storeMemory(key, value) {
        try {
            // Store in claude-flow memory system
            const memoryData = JSON.stringify({
                namespace: this.memoryNamespace,
                key,
                value,
                timestamp: new Date().toISOString()
            });
            
            // Write to local memory file as backup
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
    const command = args[0] || 'start';
    
    const monitor = new NpmVersionMonitor();
    
    (async () => {
        try {
            await monitor.init();
            
            switch (command) {
                case 'start':
                    await monitor.startMonitoring();
                    break;
                case 'check':
                    const change = await monitor.detectVersionChange();
                    if (change) {
                        console.log('Update available:', change);
                        process.exit(1); // Exit code 1 indicates update available
                    }
                    process.exit(0);
                case 'stop':
                    await monitor.stopMonitoring();
                    break;
                default:
                    console.log('Usage: npm-version-monitor.js [start|check|stop]');
                    process.exit(1);
            }
            
        } catch (error) {
            console.error('❌ Monitor failed:', error.message);
            process.exit(1);
        }
    })();
}

module.exports = NpmVersionMonitor;