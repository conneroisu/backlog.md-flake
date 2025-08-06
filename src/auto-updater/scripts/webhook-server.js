#!/usr/bin/env node
/**
 * Webhook/Polling System for Version Changes
 * Handles incoming webhooks and polling mechanisms for NPM updates
 */

const http = require('http');
const url = require('url');
const fs = require('fs').promises;
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');

class WebhookServer {
    constructor(config = {}) {
        this.port = config.port || process.env.WEBHOOK_PORT || 3000;
        this.host = config.host || process.env.WEBHOOK_HOST || 'localhost';
        this.secret = config.secret || process.env.WEBHOOK_SECRET;
        this.packageName = config.packageName || 'backlog.md';
        this.memoryNamespace = 'hive/auto-update';
        this.server = null;
        this.isListening = false;
        
        // Polling configuration
        this.enablePolling = config.enablePolling || true;
        this.pollingInterval = config.pollingInterval || 300000; // 5 minutes
        this.pollingTimer = null;
        
        // Security settings
        this.enableAuth = config.enableAuth || false;
        this.allowedIPs = config.allowedIPs || ['127.0.0.1', '::1'];
        
        // Rate limiting
        this.rateLimit = config.rateLimit || 10; // requests per minute
        this.requestCounts = new Map();
    }

    async init() {
        console.log('🔧 Initializing Webhook Server');
        await this.storeMemory('webhook_server_init', {
            port: this.port,
            host: this.host,
            enablePolling: this.enablePolling,
            pollingInterval: this.pollingInterval,
            timestamp: new Date().toISOString()
        });
    }

    verifyWebhookSignature(payload, signature) {
        if (!this.secret || !signature) {
            return !this.enableAuth; // Allow if auth is disabled
        }
        
        const expectedSignature = crypto
            .createHmac('sha256', this.secret)
            .update(payload)
            .digest('hex');
            
        return crypto.timingSafeEqual(
            Buffer.from(signature),
            Buffer.from(`sha256=${expectedSignature}`)
        );
    }

    checkRateLimit(ip) {
        const now = Date.now();
        const windowStart = now - 60000; // 1 minute window
        
        if (!this.requestCounts.has(ip)) {
            this.requestCounts.set(ip, []);
        }
        
        const requests = this.requestCounts.get(ip);
        
        // Remove old requests outside the window
        while (requests.length > 0 && requests[0] < windowStart) {
            requests.shift();
        }
        
        if (requests.length >= this.rateLimit) {
            return false; // Rate limit exceeded
        }
        
        requests.push(now);
        return true;
    }

    async handleWebhookRequest(req, res) {
        const clientIP = req.connection.remoteAddress || req.socket.remoteAddress;
        
        try {
            // Check IP allowlist
            if (this.allowedIPs.length > 0 && !this.allowedIPs.includes(clientIP)) {
                console.warn(`⚠️  Blocked request from unauthorized IP: ${clientIP}`);
                res.writeHead(403, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Forbidden' }));
                return;
            }
            
            // Check rate limit
            if (!this.checkRateLimit(clientIP)) {
                console.warn(`⚠️  Rate limit exceeded for IP: ${clientIP}`);
                res.writeHead(429, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Rate limit exceeded' }));
                return;
            }
            
            // Get request body
            let body = '';
            req.on('data', chunk => {
                body += chunk.toString();
            });
            
            req.on('end', async () => {
                try {
                    // Verify signature if auth is enabled
                    const signature = req.headers['x-hub-signature-256'];
                    if (!this.verifyWebhookSignature(body, signature)) {
                        console.warn('⚠️  Invalid webhook signature');
                        res.writeHead(401, { 'Content-Type': 'application/json' });
                        res.end(JSON.stringify({ error: 'Invalid signature' }));
                        return;
                    }
                    
                    // Parse webhook payload
                    const payload = JSON.parse(body);
                    
                    // Handle different webhook types
                    await this.processWebhookPayload(payload, clientIP);
                    
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ 
                        status: 'success', 
                        message: 'Webhook processed' 
                    }));
                    
                } catch (error) {
                    console.error('❌ Webhook processing error:', error.message);
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ 
                        error: 'Internal server error' 
                    }));
                }
            });
            
        } catch (error) {
            console.error('❌ Webhook request error:', error.message);
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Internal server error' }));
        }
    }

    async processWebhookPayload(payload, clientIP) {
        console.log('📨 Processing webhook payload...');
        
        // Store webhook event
        await this.storeMemory('webhook_received', {
            payload,
            clientIP,
            timestamp: new Date().toISOString()
        });
        
        // Check if this is an NPM package update webhook
        if (this.isNpmUpdateWebhook(payload)) {
            console.log('📦 NPM package update detected via webhook');
            await this.triggerVersionCheck('webhook');
        }
        
        // Handle custom webhook formats
        else if (payload.package === this.packageName || payload.packageName === this.packageName) {
            console.log('🎯 Direct package update webhook');
            await this.triggerVersionCheck('webhook');
        }
        
        // Generic update trigger
        else if (payload.action === 'package-update' || payload.event === 'version-released') {
            console.log('🔄 Generic update trigger webhook');
            await this.triggerVersionCheck('webhook');
        }
        
        else {
            console.log('ℹ️  Webhook received but no action needed');
        }
    }

    isNpmUpdateWebhook(payload) {
        // Check for NPM registry webhook patterns
        return (
            payload.type === 'publish' ||
            payload.event === 'package:publish' ||
            (payload.document && payload.document.name === this.packageName) ||
            (payload.name === this.packageName && payload.event === 'version')
        );
    }

    async triggerVersionCheck(source = 'unknown') {
        console.log(`🔍 Triggering version check (source: ${source})...`);
        
        try {
            const monitorScript = path.join(__dirname, 'npm-version-monitor.js');
            
            const checkProcess = spawn('node', [monitorScript, 'check'], {
                stdio: 'pipe'
            });
            
            let output = '';
            let errorOutput = '';
            
            checkProcess.stdout.on('data', (data) => {
                output += data.toString();
            });
            
            checkProcess.stderr.on('data', (data) => {
                errorOutput += data.toString();
            });
            
            checkProcess.on('close', async (code) => {
                if (code === 1) {
                    console.log('🎉 Update available, triggering update process...');
                    await this.triggerUpdateProcess();
                } else if (code === 0) {
                    console.log('✅ No updates available');
                } else {
                    console.error('❌ Version check failed:', errorOutput);
                }
                
                await this.storeMemory('version_check_triggered', {
                    source,
                    code,
                    output,
                    errorOutput,
                    timestamp: new Date().toISOString()
                });
            });
            
        } catch (error) {
            console.error('❌ Failed to trigger version check:', error.message);
            await this.storeMemory('version_check_trigger_failed', {
                source,
                error: error.message,
                timestamp: new Date().toISOString()
            });
        }
    }

    async triggerUpdateProcess() {
        console.log('🚀 Triggering full update process...');
        
        try {
            const monitorScript = path.join(__dirname, 'npm-version-monitor.js');
            
            // Start the monitoring process which will handle the update
            const updateProcess = spawn('node', [monitorScript, 'start'], {
                detached: true,
                stdio: 'ignore'
            });
            
            updateProcess.unref();
            
            await this.storeMemory('update_process_triggered', {
                pid: updateProcess.pid,
                timestamp: new Date().toISOString()
            });
            
        } catch (error) {
            console.error('❌ Failed to trigger update process:', error.message);
            throw error;
        }
    }

    async startPolling() {
        if (!this.enablePolling) {
            console.log('📊 Polling disabled');
            return;
        }
        
        console.log(`📊 Starting polling (interval: ${this.pollingInterval}ms)`);
        
        const poll = async () => {
            console.log('🔍 Polling for version updates...');
            await this.triggerVersionCheck('polling');
        };
        
        // Initial poll
        await poll();
        
        // Schedule recurring polls
        this.pollingTimer = setInterval(poll, this.pollingInterval);
        
        await this.storeMemory('polling_started', {
            interval: this.pollingInterval,
            timestamp: new Date().toISOString()
        });
    }

    async stopPolling() {
        if (this.pollingTimer) {
            clearInterval(this.pollingTimer);
            this.pollingTimer = null;
            console.log('🛑 Polling stopped');
            
            await this.storeMemory('polling_stopped', {
                timestamp: new Date().toISOString()
            });
        }
    }

    async startServer() {
        if (this.isListening) {
            console.log('⚠️  Server already running');
            return;
        }
        
        this.server = http.createServer((req, res) => {
            const parsedUrl = url.parse(req.url, true);
            
            if (req.method === 'POST' && parsedUrl.pathname === '/webhook') {
                this.handleWebhookRequest(req, res);
            } else if (req.method === 'GET' && parsedUrl.pathname === '/health') {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ 
                    status: 'healthy', 
                    timestamp: new Date().toISOString(),
                    package: this.packageName
                }));
            } else {
                res.writeHead(404, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Not found' }));
            }
        });
        
        return new Promise((resolve, reject) => {
            this.server.listen(this.port, this.host, async (error) => {
                if (error) {
                    reject(error);
                } else {
                    this.isListening = true;
                    console.log(`🌐 Webhook server listening on ${this.host}:${this.port}`);
                    console.log(`📡 Webhook endpoint: http://${this.host}:${this.port}/webhook`);
                    console.log(`🏥 Health check: http://${this.host}:${this.port}/health`);
                    
                    await this.storeMemory('server_started', {
                        host: this.host,
                        port: this.port,
                        timestamp: new Date().toISOString()
                    });
                    
                    // Start polling if enabled
                    await this.startPolling();
                    
                    resolve();
                }
            });
        });
    }

    async stopServer() {
        if (!this.isListening || !this.server) {
            console.log('⚠️  Server not running');
            return;
        }
        
        return new Promise((resolve) => {
            this.server.close(async () => {
                this.isListening = false;
                console.log('🛑 Webhook server stopped');
                
                await this.stopPolling();
                
                await this.storeMemory('server_stopped', {
                    timestamp: new Date().toISOString()
                });
                
                resolve();
            });
        });
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
    
    const config = {
        port: process.env.WEBHOOK_PORT || 3000,
        host: process.env.WEBHOOK_HOST || 'localhost',
        secret: process.env.WEBHOOK_SECRET,
        enableAuth: process.env.WEBHOOK_AUTH === 'true',
        enablePolling: process.env.ENABLE_POLLING !== 'false',
        pollingInterval: parseInt(process.env.POLLING_INTERVAL || '300000'),
        allowedIPs: process.env.ALLOWED_IPS ? process.env.ALLOWED_IPS.split(',') : ['127.0.0.1', '::1']
    };
    
    const webhookServer = new WebhookServer(config);
    
    (async () => {
        try {
            await webhookServer.init();
            
            switch (command) {
                case 'start':
                    await webhookServer.startServer();
                    
                    // Handle graceful shutdown
                    process.on('SIGTERM', async () => {
                        console.log('📡 Received SIGTERM, shutting down gracefully...');
                        await webhookServer.stopServer();
                        process.exit(0);
                    });
                    
                    process.on('SIGINT', async () => {
                        console.log('📡 Received SIGINT, shutting down gracefully...');
                        await webhookServer.stopServer();
                        process.exit(0);
                    });
                    
                    break;
                    
                case 'stop':
                    await webhookServer.stopServer();
                    break;
                    
                case 'test':
                    console.log('🧪 Testing version check trigger...');
                    await webhookServer.triggerVersionCheck('test');
                    break;
                    
                default:
                    console.log('Usage: webhook-server.js [start|stop|test]');
                    console.log('');
                    console.log('Environment variables:');
                    console.log('  WEBHOOK_PORT=3000');
                    console.log('  WEBHOOK_HOST=localhost');
                    console.log('  WEBHOOK_SECRET=your-secret');
                    console.log('  WEBHOOK_AUTH=true');
                    console.log('  ENABLE_POLLING=true');
                    console.log('  POLLING_INTERVAL=300000');
                    console.log('  ALLOWED_IPS=127.0.0.1,::1');
                    process.exit(1);
            }
            
        } catch (error) {
            console.error('❌ Webhook server failed:', error.message);
            process.exit(1);
        }
    })();
}

module.exports = WebhookServer;