# VisionOps Frontend

Modern, responsive web interface for VisionOps AI object detection platform.

## Features

### 🎨 Beautiful UI
- Modern gradient design with Tailwind CSS
- Responsive layout for desktop and mobile
- Smooth animations and transitions
- Professional color scheme

### 📊 Real-Time Dashboard
- **Total Detections**: Running count of objects detected
- **Cache Hit Rate**: Redis cache efficiency percentage
- **Images Stored**: Count of images in MinIO storage
- **Avg Inference Time**: Detection performance metrics

### 🖼️ Image Upload
- **Drag & Drop**: Intuitive file upload
- **Browse Files**: Traditional file selection
- **Preview**: Instant image preview before processing
- **Supported Formats**: JPG, PNG, WEBP

### 🎯 Detection Visualization
- **Bounding Boxes**: Color-coded boxes around detected objects
- **Confidence Scores**: Displayed with each detection
- **Interactive Canvas**: High-quality visualization
- **Detection List**: Detailed breakdown of all objects

### 📈 Live Statistics
- Real-time system health monitoring
- Cache performance metrics
- Storage statistics
- Model configuration display

## Quick Start

### Local Development

```powershell
# Navigate to frontend directory
cd frontend

# Start development server
python server.py
```

The frontend will be available at: **http://localhost:3000**

### Prerequisites

Make sure the VisionOps API is running:
```powershell
cd api
.\venv\Scripts\python.exe main.py
```

API should be accessible at: **http://localhost:8000**

## Architecture

```
frontend/
├── index.html          # Main UI structure
├── app.js             # Application logic
├── server.py          # Development server
└── README.md          # This file
```

### Technology Stack

- **HTML5**: Semantic markup
- **Tailwind CSS**: Utility-first styling (via CDN)
- **Vanilla JavaScript**: No framework dependencies
- **Canvas API**: Bounding box rendering
- **Font Awesome**: Icon library
- **FastAPI**: Static file serving

## Usage Guide

### 1. Upload Image
- **Option A**: Drag and drop an image onto the upload area
- **Option B**: Click "Browse Files" and select an image

### 2. View Results
- Detection results appear automatically
- Bounding boxes drawn on the image
- Objects listed with confidence scores

### 3. Explore Stats
- Dashboard updates every 5 seconds
- View cache efficiency
- Monitor storage usage
- Check system health

## API Integration

The frontend communicates with the backend API:

### Endpoints Used
- `GET /health` - System health check
- `GET /stats` - Service statistics
- `POST /detect` - Object detection
- `GET /metrics` - Prometheus metrics

### Configuration

API base URL is auto-detected:
- **Local**: `http://localhost:8000`
- **Production**: Same origin + `/api`

To change API URL, edit `app.js`:
```javascript
const API_BASE_URL = 'http://your-api-url:8000';
```

## Features in Detail

### Bounding Box Colors
- Each detected object gets a unique color
- Colors cycle through a predefined palette
- Colors consistent across UI elements

### Cache Indicator
- ✅ Green checkmark: Result from cache (< 10ms)
- ❌ Gray X: Fresh inference (~1000ms)

### Detection Confidence
- Displayed as percentage (0-100%)
- Color-coded by confidence level
- Average confidence calculated for all detections

### Keyboard Shortcuts
- `Escape`: Clear current image
- `Ctrl/Cmd + O`: Open file picker

## Performance

- **Page Load**: < 1s (CDN assets)
- **Image Upload**: Instant preview
- **Detection Display**: < 100ms rendering
- **Stats Refresh**: Every 5 seconds
- **Health Check**: Every 10 seconds

## Browser Support

- Chrome/Edge: ✅ Fully supported
- Firefox: ✅ Fully supported
- Safari: ✅ Fully supported
- Mobile browsers: ✅ Responsive design

## Troubleshooting

### Frontend not loading
```powershell
# Check if server is running
curl http://localhost:3000
```

### API connection issues
```powershell
# Verify API is running
curl http://localhost:8000/health
```

### CORS errors
- Ensure API allows CORS for frontend origin
- Check browser console for specific errors

## Production Deployment

For production, use Nginx or serve via Kubernetes:

```nginx
server {
    listen 80;
    server_name visionops.example.com;
    
    location / {
        root /app/frontend;
        try_files $uri $uri/ /index.html;
    }
    
    location /api/ {
        proxy_pass http://api-service:8000/;
    }
}
```

## Future Enhancements

- [ ] Batch image upload
- [ ] Detection history
- [ ] Export results (JSON/CSV)
- [ ] Custom confidence threshold slider
- [ ] Video detection support
- [ ] Dark mode toggle
- [ ] Mobile camera integration
- [ ] Real-time WebSocket updates

## Contributing

When adding features:
1. Maintain responsive design
2. Follow existing color scheme
3. Keep JavaScript vanilla (no frameworks)
4. Test on multiple browsers
5. Update this README

## License

Part of the VisionOps project.
