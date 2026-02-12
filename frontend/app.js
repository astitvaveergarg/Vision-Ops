// VisionOps Frontend Application
const API_BASE_URL = window.location.origin.includes('localhost') 
    ? 'http://localhost:8000' 
    : '/api';

// State
let currentImage = null;
let detectionResults = null;
let availableModels = [];
let selectedModel = 'yolov8n';
let stats = {
    totalDetections: 0,
    inferenceTime: 0
};

// DOM Elements
const uploadArea = document.getElementById('uploadArea');
const fileInput = document.getElementById('fileInput');
const browseBtn = document.getElementById('browseBtn');
const clearBtn = document.getElementById('clearBtn');
const previewSection = document.getElementById('previewSection');
const previewImage = document.getElementById('previewImage');
const processingIndicator = document.getElementById('processingIndicator');
const resultsPlaceholder = document.getElementById('resultsPlaceholder');
const resultsContent = document.getElementById('resultsContent');
const detectionCanvas = document.getElementById('detectionCanvas');
const detectionsList = document.getElementById('detectionsList');
const modelSelector = document.getElementById('modelSelector');
const modelDescription = document.getElementById('modelDescription');

// Colors for bounding boxes
const COLORS = [
    '#FF6B6B', '#4ECDC4', '#45B7D1', '#FFA07A', '#98D8C8',
    '#F7DC6F', '#BB8FCE', '#85C1E2', '#F8B195', '#C06C84'
];

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initializeEventListeners();
    fetchModels();
    fetchStats();
    checkHealth();
    
    // Refresh stats every 5 seconds
    setInterval(fetchStats, 5000);
    setInterval(checkHealth, 10000);
});

function initializeEventListeners() {
    // Browse button
    browseBtn.addEventListener('click', () => fileInput.click());
    
    // File input change
    fileInput.addEventListener('change', handleFileSelect);
    
    // Model selector change
    modelSelector.addEventListener('change', (e) => {
        selectedModel = e.target.value;
        updateModelDescription();
    });
    
    // Drag and drop
    uploadArea.addEventListener('dragover', (e) => {
        e.preventDefault();
        uploadArea.classList.add('dragover');
    });
    
    uploadArea.addEventListener('dragleave', () => {
        uploadArea.classList.remove('dragover');
    });
    
    uploadArea.addEventListener('drop', (e) => {
        e.preventDefault();
        uploadArea.classList.remove('dragover');
        
        const files = e.dataTransfer.files;
        if (files.length > 0) {
            handleFile(files[0]);
        }
    });
    
    // Clear button
    clearBtn.addEventListener('click', clearImage);
}

function handleFileSelect(e) {
    const file = e.target.files[0];
    if (file) {
        handleFile(file);
    }
}

function handleFile(file) {
    if (!file.type.startsWith('image/')) {
        showNotification('Please select a valid image file', 'error');
        return;
    }
    
    currentImage = file;
    
    // Show preview
    const reader = new FileReader();
    reader.onload = (e) => {
        previewImage.src = e.target.result;
        previewSection.classList.remove('hidden');
    };
    reader.readAsDataURL(file);
    
    // Upload and detect
    uploadAndDetect(file);
}

async function fetchModels() {
    try {
        const response = await fetch(`${API_BASE_URL}/models`);
        if (!response.ok) return;
        
        const data = await response.json();
        availableModels = data.models || [];
        
        // Update model selector with real data
        updateModelSelector();
        updateModelDescription();
        
    } catch (error) {
        console.error('Models fetch error:', error);
        modelDescription.textContent = 'Unable to load models';
    }
}

function updateModelSelector() {
    if (availableModels.length === 0) return;
    
    modelSelector.innerHTML = '';
    
    const speedIcons = ['🐌🐌', '🐌', '⚡', '⚡⚡', '⚡⚡⚡'];
    
    availableModels.forEach(model => {
        const option = document.createElement('option');
        option.value = model.id;
        option.textContent = `${model.name} - ${speedIcons[model.speed_rating - 1]} (${model.size_mb}MB, mAP: ${model.map_score}%)`;
        
        if (model.downloaded) {
            option.textContent += ' ✓';
        }
        
        modelSelector.appendChild(option);
    });
}

function updateModelDescription() {
    const model = availableModels.find(m => m.id === selectedModel);
    if (!model) {
        modelDescription.textContent = 'Model information not available';
        return;
    }
    
    const status = model.downloaded ? '✓ Downloaded' : '⬇ Will download on first use';
    const loaded = model.loaded ? ' | ⚡ Loaded in memory' : '';
    
    modelDescription.innerHTML = `
        <span class="font-medium">${model.description}</span> |
        <span class="text-purple-600">mAP: ${model.map_score}%</span> |
        <span class="text-green-600">${status}</span>${loaded}
    `;
}

async function uploadAndDetect(file) {
    // Show processing indicator
    processingIndicator.classList.remove('hidden');
    resultsPlaceholder.classList.add('hidden');
    resultsContent.classList.add('hidden');
    
    const formData = new FormData();
    formData.append('file', file);
    
    const startTime = Date.now();
    
    try {
        // Send with model parameter
        const response = await fetch(`${API_BASE_URL}/detect?model=${selectedModel}`, {
            method: 'POST',
            body: formData
        });
        
        if (!response.ok) {
            throw new Error(`Detection failed: ${response.statusText}`);
        }
        
        const data = await response.json();
        const inferenceTime = Date.now() - startTime;
        
        detectionResults = data;
        stats.inferenceTime = inferenceTime;
        stats.totalDetections += data.detection_count;
        
        // Update UI
        displayResults(data, inferenceTime);
        
    } catch (error) {
        console.error('Detection error:', error);
        showNotification(`Error: ${error.message}`, 'error');
    } finally {
        processingIndicator.classList.add('hidden');
    }
}

function displayResults(data, inferenceTime) {
    resultsPlaceholder.classList.add('hidden');
    resultsContent.classList.remove('hidden');
    
    // Update detection count
    document.getElementById('detectionCount').textContent = data.detection_count;
    
    // Calculate average confidence
    const avgConf = data.detections.length > 0
        ? (data.detections.reduce((sum, d) => sum + d.confidence, 0) / data.detections.length * 100).toFixed(1)
        : 0;
    document.getElementById('avgConfidence').textContent = `${avgConf}%`;
    
    // Update cached status with model info
    const modelUsed = availableModels.find(m => m.id === data.model_id);
    const modelBadge = modelUsed ? `<span class="text-xs text-purple-600">${modelUsed.name}</span>` : '';
    
    const cachedIcon = data.cached 
        ? `<i class="fas fa-check-circle text-green-500"></i>${modelBadge}`
        : `<i class="fas fa-times-circle text-gray-400"></i>${modelBadge}`;
    document.getElementById('cachedStatus').innerHTML = cachedIcon;
    
    // Draw bounding boxes
    drawBoundingBoxes(previewImage.src, data.detections);
    
    // Display detection list
    displayDetectionList(data.detections);
    
    // Update stats
    updateStatsDisplay(inferenceTime, data.cached);
}

function drawBoundingBoxes(imageSrc, detections) {
    const img = new Image();
    img.onload = () => {
        const canvas = detectionCanvas;
        const ctx = canvas.getContext('2d');
        
        // Set canvas size to match image
        canvas.width = img.width;
        canvas.height = img.height;
        
        // Draw image
        ctx.drawImage(img, 0, 0);
        
        // Draw bounding boxes
        detections.forEach((detection, index) => {
            const [x1, y1, x2, y2] = detection.bbox;
            const color = COLORS[index % COLORS.length];
            
            // Draw box
            ctx.strokeStyle = color;
            ctx.lineWidth = 3;
            ctx.strokeRect(x1, y1, x2 - x1, y2 - y1);
            
            // Draw label background
            const label = `${detection.class} ${(detection.confidence * 100).toFixed(1)}%`;
            ctx.font = 'bold 16px Inter';
            const textWidth = ctx.measureText(label).width;
            
            ctx.fillStyle = color;
            ctx.fillRect(x1, y1 - 30, textWidth + 10, 30);
            
            // Draw label text
            ctx.fillStyle = 'white';
            ctx.fillText(label, x1 + 5, y1 - 10);
        });
    };
    img.src = imageSrc;
}

function displayDetectionList(detections) {
    detectionsList.innerHTML = '';
    
    if (detections.length === 0) {
        detectionsList.innerHTML = `
            <div class="text-center py-8">
                <i class="fas fa-search text-gray-300 text-4xl mb-2"></i>
                <p class="text-gray-400">No objects detected in this image</p>
            </div>
        `;
        return;
    }
    
    detections.forEach((detection, index) => {
        const color = COLORS[index % COLORS.length];
        const confidence = (detection.confidence * 100).toFixed(1);
        
        const detectionItem = document.createElement('div');
        detectionItem.className = 'detection-badge flex items-center justify-between p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition';
        detectionItem.innerHTML = `
            <div class="flex items-center">
                <div class="w-3 h-3 rounded-full mr-3" style="background-color: ${color}"></div>
                <div>
                    <p class="font-semibold text-gray-800 capitalize">${detection.class}</p>
                    <p class="text-xs text-gray-500">Bounding Box: [${detection.bbox.map(v => v.toFixed(0)).join(', ')}]</p>
                </div>
            </div>
            <div class="text-right">
                <p class="text-lg font-bold" style="color: ${color}">${confidence}%</p>
                <p class="text-xs text-gray-500">Confidence</p>
            </div>
        `;
        detectionsList.appendChild(detectionItem);
    });
}

function updateStatsDisplay(inferenceTime, cached) {
    document.getElementById('totalDetections').textContent = stats.totalDetections;
    document.getElementById('avgInference').textContent = cached ? '<10ms' : `${inferenceTime}ms`;
}

async function fetchStats() {
    try {
        const response = await fetch(`${API_BASE_URL}/stats`);
        if (!response.ok) return;
        
        const data = await response.json();
        
        // Update cache stats
        if (data.cache) {
            const hits = data.cache.keyspace_hits || 0;
            const misses = data.cache.keyspace_misses || 0;
            const total = hits + misses;
            const hitRate = total > 0 ? ((hits / total) * 100).toFixed(1) : 0;
            document.getElementById('cacheHitRate').textContent = `${hitRate}%`;
        }
        
        // Update storage stats
        if (data.storage) {
            document.getElementById('imagesStored').textContent = data.storage.object_count || 0;
        }
        
        // Update model info
        if (data.model) {
            document.getElementById('confThreshold').textContent = `${(data.model.conf_threshold * 100)}%`;
            document.getElementById('classCount').textContent = `${data.model.classes?.length || 80} objects`;
        }
        
    } catch (error) {
        console.error('Stats fetch error:', error);
    }
}

async function checkHealth() {
    try {
        const response = await fetch(`${API_BASE_URL}/health`);
        if (!response.ok) throw new Error('Health check failed');
        
        const data = await response.json();
        const allHealthy = data.redis && data.minio && data.model;
        
        const healthStatus = document.getElementById('healthStatus');
        if (allHealthy) {
            healthStatus.innerHTML = `
                <span class="w-3 h-3 bg-green-400 rounded-full animate-pulse mr-2"></span>
                <span class="text-white text-sm">System Healthy</span>
            `;
        } else {
            healthStatus.innerHTML = `
                <span class="w-3 h-3 bg-red-400 rounded-full animate-pulse mr-2"></span>
                <span class="text-white text-sm">System Degraded</span>
            `;
        }
    } catch (error) {
        const healthStatus = document.getElementById('healthStatus');
        healthStatus.innerHTML = `
            <span class="w-3 h-3 bg-red-400 rounded-full mr-2"></span>
            <span class="text-white text-sm">System Offline</span>
        `;
    }
}

function clearImage() {
    currentImage = null;
    detectionResults = null;
    fileInput.value = '';
    previewSection.classList.add('hidden');
    resultsPlaceholder.classList.remove('hidden');
    resultsContent.classList.add('hidden');
}

function showNotification(message, type = 'info') {
    // Simple notification (could be enhanced with a toast library)
    alert(message);
}

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {
    // Escape to clear
    if (e.key === 'Escape') {
        clearImage();
    }
    
    // Ctrl/Cmd + O to open file
    if ((e.ctrlKey || e.metaKey) && e.key === 'o') {
        e.preventDefault();
        fileInput.click();
    }
});
