// Florida Server Control Script
let callbackId = 0;

// Execute shell command via KSU/Magisk
function exec(cmd, options = {}) {
    return new Promise((resolve, reject) => {
        const callback = `exec_callback_${Date.now()}_${callbackId++}`;

        window[callback] = (errno, stdout, stderr) => {
            resolve({ errno, stdout, stderr });
            delete window[callback];
        };

        try {
            ksu.exec(cmd, JSON.stringify(options), callback);
        } catch (err) {
            reject(err);
            delete window[callback];
        }
    });
}

function toast(msg) {
    ksu.toast(msg);
}

// DOM Elements
const serverStatus = document.getElementById('serverStatus');
const serverStatusText = document.getElementById('serverStatusText');
const toggleServerBtn = document.getElementById('toggleServerBtn');
const saveSettingsBtn = document.getElementById('saveSettingsBtn');
const versionSelect = document.getElementById('versionSelect');
const portInput = document.getElementById('portInput');
const customParams = document.getElementById('customParams');
const warningDialog = document.getElementById('warningDialog');
const cancelStop = document.getElementById('cancelStop');
const confirmStop = document.getElementById('confirmStop');

let isRunning = false;
const MODULE_CFG = '/data/adb/modules/magisk-hluda/module.cfg';

// Load current settings
async function loadSettings() {
    try {
        // Check if config file exists
        const { errno } = await exec(`test -f ${MODULE_CFG}`);
        if (errno !== 0) {
            await createDefaultConfig();
            return;
        }

        // Load version
        const { stdout: version } = await exec(`grep "^version=" ${MODULE_CFG} | cut -d= -f2`);
        const versionValue = version.trim();
        if (versionValue) {
            versionSelect.value = versionValue;
        }

        // Load port
        const { stdout: port } = await exec(`grep "^port=" ${MODULE_CFG} | cut -d= -f2`);
        portInput.value = port.trim() || '27042';

        // Load parameters
        const { stdout: params } = await exec(`grep "^parameters=" ${MODULE_CFG} | cut -d= -f2-`);
        customParams.value = params.trim() || '';

    } catch (err) {
        console.error('Failed to load settings:', err);
        toast(`Failed to load settings: ${err.message}`);
    }
}

// Create default config
async function createDefaultConfig() {
    try {
        const status = isRunning ? 1 : 0;
        const config = `port=${portInput.value}\nparameters=${customParams.value}\nstatus=${status}\nversion=${versionSelect.value}`;
        await exec(`echo '${config}' > ${MODULE_CFG}`);
        console.log('Created module.cfg with default values');
    } catch (err) {
        console.error('Error creating module.cfg:', err);
        toast('Failed to initialize config file');
    }
}

// Save settings
async function saveSettings() {
    try {
        // Validate port
        const port = parseInt(portInput.value);
        if (isNaN(port) || port < 1 || port > 65535) {
            toast('Invalid port number. Using default port 27042');
            portInput.value = '27042';
        }

        // Check if config exists
        const { errno } = await exec(`test -f ${MODULE_CFG}`);
        if (errno !== 0) {
            await createDefaultConfig();
            return;
        }

        // Update version
        await exec(`sed -i "s/^version=.*/version=${versionSelect.value}/" ${MODULE_CFG}`);

        // Update port
        await exec(`sed -i "s/^port=.*/port=${portInput.value}/" ${MODULE_CFG}`);

        // Update parameters (escape special characters)
        const params = customParams.value
            .replace(/\//g, '\\/')
            .replace(/'/g, "\\'")
            .replace(/"/g, '\\"');
        await exec(`sed -i "s/^parameters=.*/parameters=${params}/" ${MODULE_CFG}`);

        // Update status
        const status = isRunning ? 1 : 0;
        await exec(`sed -i "s/^status=.*/status=${status}/" ${MODULE_CFG}`);

        toast('Settings saved successfully');
    } catch (err) {
        console.error('Failed to save settings:', err);
        toast(`Failed to save settings: ${err.message}`);
    }
}

// Update UI status
function updateStatus(running) {
    if (isRunning === running) return;

    isRunning = running;
    serverStatus.classList.toggle('status-running', running);
    serverStatus.classList.toggle('status-stopped', !running);
    serverStatusText.textContent = running ? 'Running' : 'Stopped';
    toggleServerBtn.textContent = running ? 'Stop Server' : 'Start Server';
    toggleServerBtn.classList.toggle('btn-danger', running);
    toggleServerBtn.classList.toggle('btn-primary', !running);

    // Update module.prop description
    updateModuleProp(running);
}

// Update module.prop description
async function updateModuleProp(running) {
    const version = versionSelect.value === '17.5.1' || versionSelect.value === '1751' ? '17.5.1' : '16.0.3';
    const desc = running ? `Running✅ | v${version}` : `Stopped❌ | v${version}`;
    try {
        await exec(`sed -i "s/^description=.*/description=[${desc}]/" /data/adb/modules/magisk-hluda/module.prop`);
    } catch (err) {
        console.error('Failed to update module.prop:', err);
    }
}

// Check server status
async function checkStatus() {
    try {
        const { errno } = await exec('pgrep -f florida');
        updateStatus(errno === 0);
    } catch (err) {
        console.error('Error checking server status:', err);
        updateStatus(false);
    }
}

// Start server
async function startServer(port, params, version) {
    // Determine binary name based on version
    const binary = version === '17.5.1' || version === '1751' ? 'florida-17.5.1' : 'florida-1603';
    const cmd = `${binary} -D -l 0.0.0.0:${port}`;
    const fullCmd = params ? `${cmd} ${params}` : cmd;

    try {
        const { errno, stderr } = await exec(fullCmd);

        if (errno !== 0 || stderr.trim()) {
            toast(`Failed to start server: ${stderr.trim() || 'Unknown error occurred'}`);
            updateStatus(false);
            return;
        }

        // Wait a bit and check status
        setTimeout(checkStatus, 500);
        toast('Server started successfully');
    } catch (err) {
        toast(`Failed to start server: ${err.message}`);
        updateStatus(false);
    }
}

// Stop server
async function stopServer() {
    try {
        const { errno } = await exec('pkill -SIGKILL -f florida');

        if (errno !== 0) {
            throw new Error('Server not running');
        }

        updateStatus(false);
        toast('Server stopped successfully');
    } catch (err) {
        toast(`Failed to stop server: ${err.message}`);
    }
}

// Event Listeners
// Version change handler - restart server if running
versionSelect.addEventListener('change', async () => {
    if (isRunning) {
        toast('切换版本中...');
        const port = portInput.value || '27042';
        const params = customParams.value;
        const version = versionSelect.value;

        // Stop old version
        await exec('pkill -SIGKILL -f florida');
        await new Promise(resolve => setTimeout(resolve, 500));

        // Save new version to config
        await saveSettings();

        // Start new version
        await startServer(port, params, version);
    } else {
        // Just save the setting
        await saveSettings();
        toast('版本已切换，启动服务后生效');
    }
});

saveSettingsBtn.addEventListener('click', saveSettings);

toggleServerBtn.addEventListener('click', async () => {
    const port = portInput.value || '27042';
    const params = customParams.value;
    const version = versionSelect.value;

    if (isRunning) {
        // Show warning dialog
        warningDialog.style.display = 'flex';
    } else {
        await saveSettings();
        await startServer(port, params, version);
    }
});

cancelStop.addEventListener('click', () => {
    warningDialog.style.display = 'none';
});

confirmStop.addEventListener('click', async () => {
    warningDialog.style.display = 'none';
    await saveSettings();
    await stopServer();
});

// Initialize
loadSettings().then(() => {
    checkStatus();
    setInterval(checkStatus, 500);
});
