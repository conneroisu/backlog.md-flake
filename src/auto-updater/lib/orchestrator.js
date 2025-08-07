#!/usr/bin/env node
/**
 * Auto-Updater Orchestrator
 * Main orchestration system that coordinates all auto-update components
 */

const fs = require('fs').promises;
const path = require('path');
const EventEmitter = require('events');

// Import all components
const NpmVersionMonitor = require('../scripts/npm-version-monitor');
const FlakeUpdater = require('../scripts/flake-updater');
const GitAutomation = require('../scripts/git-automation');
const WebhookServer = require('../scripts/webhook-server');
const RecoverySystem = require('../scripts/recovery-system');
const ValidationPipeline = require('../scripts/validation-pipeline');

class AutoUpdaterOrchestrator extends EventEmitter {
    constructor(configPath = null) {
        super();
        
        this.configPath = configPath || path.join(__dirname, '../config/auto-updater.json');
        this.config = null;
        this.components = {};
        this.isRunning = false;
        this.currentUpdate = null;
        this.memoryNamespace = 'hive/auto-update';
        
        // Component instances
        this.monitor = null;
        this.updater = null;
        this.gitAuto = null;
        this.webhookServer = null;
        this.recovery = null;
        this.validation = null;
    }

    async init() {
        console.log('🚀 Initializing Auto-Updater Orchestrator');
        
        // Load configuration
        await this.loadConfig();
        
        // Initialize components
        await this.initializeComponents();
        
        // Setup event listeners
        this.setupEventHandlers();
        
        console.log('✅ Auto-Updater Orchestrator initialized');
        
        await this.storeMemory('orchestrator_init', {
            config: this.config,
            timestamp: new Date().toISOString()
        });
    }

    async loadConfig() {
        try {
            console.log(`📋 Loading configuration from ${this.configPath}`);
            const configContent = await fs.readFile(this.configPath, 'utf8');
            this.config = JSON.parse(configContent);
            
            // Set environment variables from config
            process.env.WEBHOOK_PORT = this.config.monitoring.webhook.port;
            process.env.WEBHOOK_HOST = this.config.monitoring.webhook.host;
            process.env.ENABLE_GIT_PUSH = this.config.git.enablePush;
            process.env.ENABLE_GIT_PR = this.config.git.enablePR;
            
        } catch (error) {
            console.error('❌ Failed to load configuration:', error.message);
            throw new Error(`Configuration loading failed: ${error.message}`);
        }
    }

    async initializeComponents() {
        console.log('🔧 Initializing components...');
        
        try {
            // Initialize NPM Version Monitor
            this.monitor = new NpmVersionMonitor({
                packageName: this.config.packageName,
                currentVersion: this.config.currentVersion,
                registryUrl: this.config.registryUrl,
                checkInterval: this.config.monitoring.checkInterval
            });
            await this.monitor.init();
            
            // Initialize Flake Updater
            this.updater = new FlakeUpdater({
                flakeFile: path.resolve(this.config.paths.flakeFile),
                flakeLockFile: path.resolve(this.config.paths.flakeLockFile),
                packageName: this.config.packageName
            });
            await this.updater.init();
            
            // Initialize Git Automation
            this.gitAuto = new GitAutomation({
                repoPath: path.resolve(this.config.paths.repoPath),
                branch: this.config.git.branch,
                baseBranch: this.config.git.baseBranch,
                commitPrefix: this.config.git.commitPrefix,
                enablePush: this.config.git.enablePush,
                enablePR: this.config.git.enablePR
            });
            await this.gitAuto.init();
            
            // Initialize Webhook Server
            this.webhookServer = new WebhookServer({
                port: this.config.monitoring.webhook.port,
                host: this.config.monitoring.webhook.host,
                enableAuth: this.config.monitoring.webhook.enableAuth,
                allowedIPs: this.config.monitoring.webhook.allowedIPs,
                enablePolling: this.config.monitoring.polling.enabled,
                pollingInterval: this.config.monitoring.polling.interval,
                packageName: this.config.packageName
            });
            await this.webhookServer.init();
            
            // Initialize Recovery System
            this.recovery = new RecoverySystem({
                backupDir: path.resolve(this.config.paths.backupDir),
                maxBackups: this.config.updates.maxBackups,
                repoPath: path.resolve(this.config.paths.repoPath)
            });
            await this.recovery.init();
            
            // Initialize Validation Pipeline
            this.validation = new ValidationPipeline({
                repoPath: path.resolve(this.config.paths.repoPath),
                testSuites: this.config.updates.validation.testSuites,
                enablePerformanceTests: this.config.updates.validation.enablePerformanceTests,
                enableSecurityScans: this.config.updates.validation.enableSecurityScans
            });
            await this.validation.init();
            
            console.log('✅ All components initialized');
            
        } catch (error) {
            console.error('❌ Component initialization failed:', error.message);
            throw error;
        }
    }

    setupEventHandlers() {
        console.log('🔗 Setting up event handlers...');
        
        // Handle version changes
        this.on('versionChangeDetected', this.handleVersionChange.bind(this));
        
        // Handle update completion
        this.on('updateCompleted', this.handleUpdateCompleted.bind(this));
        
        // Handle update failure
        this.on('updateFailed', this.handleUpdateFailed.bind(this));
        
        // Handle rollback
        this.on('rollbackRequired', this.handleRollback.bind(this));
        
        // Handle validation failure
        this.on('validationFailed', this.handleValidationFailed.bind(this));
    }

    async start() {
        if (this.isRunning) {
            console.log('⚠️  Orchestrator already running');
            return;
        }
        
        console.log('▶️  Starting Auto-Updater Orchestrator');
        this.isRunning = true;
        
        try {
            // Start webhook server if enabled
            if (this.config.monitoring.webhook.enabled) {
                await this.webhookServer.startServer();
            }
            
            // Start monitoring if enabled
            if (this.config.monitoring.enabled) {
                // Override the monitor's triggerUpdate to emit our events
                const originalTriggerUpdate = this.monitor.triggerUpdate.bind(this.monitor);
                this.monitor.triggerUpdate = async (changeInfo) => {
                    this.emit('versionChangeDetected', changeInfo);
                    return originalTriggerUpdate(changeInfo);
                };
                
                await this.monitor.startMonitoring();
            }
            
            console.log('🎯 Auto-Updater Orchestrator is running');
            
            await this.storeMemory('orchestrator_started', {
                timestamp: new Date().toISOString()
            });
            
        } catch (error) {
            console.error('❌ Failed to start orchestrator:', error.message);
            this.isRunning = false;
            throw error;
        }
    }

    async stop() {
        if (!this.isRunning) {
            console.log('⚠️  Orchestrator not running');
            return;
        }
        
        console.log('⏹️  Stopping Auto-Updater Orchestrator');
        this.isRunning = false;
        
        try {
            // Stop monitoring
            if (this.monitor) {
                await this.monitor.stopMonitoring();
            }
            
            // Stop webhook server
            if (this.webhookServer) {
                await this.webhookServer.stopServer();
            }
            
            // Wait for current update to complete
            if (this.currentUpdate) {
                console.log('⏳ Waiting for current update to complete...');
                await this.currentUpdate;
            }
            
            console.log('✅ Auto-Updater Orchestrator stopped');
            
            await this.storeMemory('orchestrator_stopped', {
                timestamp: new Date().toISOString()
            });
            
        } catch (error) {
            console.error('❌ Error stopping orchestrator:', error.message);
        }
    }

    async handleVersionChange(changeInfo) {
        if (this.currentUpdate) {
            console.log('⚠️  Update already in progress, skipping...');
            return;
        }
        
        console.log('🎉 Version change detected, starting update process...');
        
        this.currentUpdate = this.performUpdate(changeInfo);
        
        try {
            await this.currentUpdate;
        } finally {
            this.currentUpdate = null;
        }
    }

    async performUpdate(changeInfo) {
        const updateId = `update-${Date.now()}`;
        
        try {
            console.log(`🚀 Starting update ${updateId}: ${changeInfo.oldVersion} → ${changeInfo.newVersion}`);
            
            await this.storeMemory(`update_started_${updateId}`, {
                updateId,
                changeInfo,
                timestamp: new Date().toISOString()
            });
            
            // Step 1: Run validation pipeline (pre-update)
            if (this.config.updates.strictValidation) {
                console.log('🔍 Running pre-update validation...');
                const preValidation = await this.validation.runValidationPipeline(changeInfo, {
                    skipTests: ['integration-test'], // Skip integration test before update
                    strictMode: false
                });
                
                if (!preValidation.success) {
                    console.warn('⚠️  Pre-update validation had issues, but continuing...');
                }
            }
            
            // Step 2: Perform flake update
            console.log('📦 Updating flake...');
            const updateSuccess = await this.updater.performUpdate(changeInfo);
            
            if (!updateSuccess) {
                throw new Error('Flake update failed');
            }
            
            // Step 3: Run validation pipeline (post-update)
            console.log('🔍 Running post-update validation...');
            const postValidation = await this.validation.runValidationPipeline(changeInfo, {
                strictMode: this.config.updates.strictValidation,
                timeoutMs: this.config.updates.validation.timeoutMs
            });
            
            if (!postValidation.success) {
                this.emit('validationFailed', { updateId, changeInfo, validation: postValidation });
                return;
            }
            
            // Step 4: Git operations
            if (this.config.git.enabled) {
                console.log('📝 Performing Git operations...');
                const gitResult = await this.gitAuto.performGitWorkflow(changeInfo);
                
                await this.storeMemory(`git_result_${updateId}`, {
                    updateId,
                    gitResult,
                    timestamp: new Date().toISOString()
                });
            }
            
            // Step 5: Update configuration with new version
            await this.updateConfigVersion(changeInfo.newVersion);
            
            console.log('🎉 Update completed successfully!');
            
            this.emit('updateCompleted', {
                updateId,
                changeInfo,
                validation: postValidation
            });
            
        } catch (error) {
            console.error(`❌ Update ${updateId} failed:`, error.message);
            
            this.emit('updateFailed', {
                updateId,
                changeInfo,
                error: error.message
            });
        }
    }

    async handleUpdateCompleted(data) {
        console.log('✅ Update completed successfully');
        
        if (this.config.notifications.onSuccess) {
            await this.sendNotification('success', data);
        }
        
        // Cleanup old backups
        await this.recovery.cleanupOldBackups();
        
        await this.storeMemory('update_completed', data);
    }

    async handleUpdateFailed(data) {
        console.error('❌ Update failed');
        
        if (this.config.notifications.onFailure) {
            await this.sendNotification('failure', data);
        }
        
        if (this.config.updates.enableRollback) {
            this.emit('rollbackRequired', data);
        }
        
        await this.storeMemory('update_failed', data);
    }

    async handleValidationFailed(data) {
        console.error('❌ Validation failed');
        
        if (this.config.updates.enableRollback && this.config.updates.strictValidation) {
            this.emit('rollbackRequired', data);
        }
    }

    async handleRollback(data) {
        console.log('⏪ Initiating rollback...');
        
        try {
            const backups = await this.recovery.listBackups();
            if (backups.length === 0) {
                throw new Error('No backups available for rollback');
            }
            
            const latestBackup = backups[0];
            const rollbackResult = await this.recovery.performRollback(latestBackup.path, {
                skipGitReset: false,
                force: false
            });
            
            console.log('✅ Rollback completed successfully');
            
            if (this.config.notifications.onRollback) {
                await this.sendNotification('rollback', {
                    ...data,
                    rollbackResult
                });
            }
            
            await this.storeMemory('rollback_completed', {
                ...data,
                rollbackResult,
                timestamp: new Date().toISOString()
            });
            
        } catch (error) {
            console.error('❌ Rollback failed:', error.message);
            
            await this.storeMemory('rollback_failed', {
                ...data,
                error: error.message,
                timestamp: new Date().toISOString()
            });
        }
    }

    async sendNotification(type, data) {
        // Placeholder for notification system
        // In a real implementation, this could send emails, Slack messages, etc.
        console.log(`📧 Notification (${type}):`, {
            type,
            timestamp: new Date().toISOString(),
            summary: data
        });
    }

    async updateConfigVersion(newVersion) {
        this.config.currentVersion = newVersion;
        await fs.writeFile(this.configPath, JSON.stringify(this.config, null, 2));
        
        console.log(`📋 Configuration updated to version ${newVersion}`);
    }

    async getStatus() {
        const recoveryStatus = await this.recovery.getSystemStatus();
        
        return {
            isRunning: this.isRunning,
            currentUpdate: this.currentUpdate !== null,
            config: {
                packageName: this.config.packageName,
                currentVersion: this.config.currentVersion,
                autoUpdate: this.config.updates.autoUpdate,
                monitoring: this.config.monitoring.enabled
            },
            components: {
                webhook: this.webhookServer?.isListening || false,
                monitoring: this.monitor?.isRunning || false,
                backups: recoveryStatus.backupCount
            },
            lastCheck: new Date().toISOString()
        };
    }

    async triggerManualUpdate() {
        if (!this.config.updates.autoUpdate) {
            throw new Error('Manual updates not allowed when autoUpdate is disabled');
        }
        
        console.log('🎯 Triggering manual update check...');
        
        const changeInfo = await this.monitor.detectVersionChange();
        
        if (changeInfo) {
            this.emit('versionChangeDetected', changeInfo);
            return changeInfo;
        } else {
            console.log('ℹ️  No updates available');
            return null;
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
    const command = args[0] || 'start';
    const configPath = args[1];
    
    const orchestrator = new AutoUpdaterOrchestrator(configPath);
    
    (async () => {
        try {
            await orchestrator.init();
            
            switch (command) {
                case 'start':
                    await orchestrator.start();
                    
                    // Handle graceful shutdown
                    process.on('SIGTERM', async () => {
                        console.log('📡 Received SIGTERM, shutting down gracefully...');
                        await orchestrator.stop();
                        process.exit(0);
                    });
                    
                    process.on('SIGINT', async () => {
                        console.log('📡 Received SIGINT, shutting down gracefully...');
                        await orchestrator.stop();
                        process.exit(0);
                    });
                    
                    break;
                    
                case 'stop':
                    await orchestrator.stop();
                    break;
                    
                case 'status':
                    const status = await orchestrator.getStatus();
                    console.log('📊 Auto-Updater Status:');
                    console.log(JSON.stringify(status, null, 2));
                    break;
                    
                case 'update':
                    const updateResult = await orchestrator.triggerManualUpdate();
                    if (updateResult) {
                        console.log('🎉 Update triggered:', updateResult);
                        // Keep the process alive to complete the update
                        await new Promise(resolve => setTimeout(resolve, 60000));
                    }
                    break;
                    
                default:
                    console.log('Usage: orchestrator.js [start|stop|status|update] [config-path]');
                    console.log('');
                    console.log('Commands:');
                    console.log('  start    - Start the auto-updater orchestrator');
                    console.log('  stop     - Stop the running orchestrator');
                    console.log('  status   - Show current status');
                    console.log('  update   - Trigger manual update check');
                    console.log('');
                    console.log('Options:');
                    console.log('  config-path  - Path to configuration file');
                    process.exit(1);
            }
            
        } catch (error) {
            console.error('❌ Orchestrator failed:', error.message);
            process.exit(1);
        }
    })();
}

module.exports = AutoUpdaterOrchestrator;