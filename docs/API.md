# 📡 VisionOps API Documentation

> **Complete API reference** - Endpoints, request/response formats, error handling, and examples

---

## 📑 Table of Contents

- [Base URL](#base-url)
- [Authentication](#authentication)
- [Endpoints](#endpoints)
  - [Health Check](#health-check)
  - [Readiness Check](#readiness-check)
  - [Object Detection](#object-detection)
  - [Metrics](#metrics)
- [Request/Response Formats](#requestresponse-formats)
- [Error Handling](#error-handling)
- [Rate Limiting](#rate-limiting)
- [Examples](#examples)
- [SDKs & Client Libraries](#sdks--client-libraries)

---

## Base URL

### Local Development
```
http://localhost:8000
```

### Minikube
```
http://<minikube-ip>:<nodeport>
# Get actual URL:
minikube service vision-api -n vision-app --url
```

### Dev/Prod (via Port-forward)
```bash
kubectl port-forward -n vision-app svc/vision-api 8000:8000
# Then: http://localhost:8000
```

### Production (via CDN)
```
AWS: https://<cloudfront-domain>
Azure: https://<frontdoor-domain>
```

---

## Authentication

**Current Version**: No authentication (for demo purposes)

**Future Versions** (planned):
- API Key authentication (Header: `X-API-Key`)
- JWT bearer tokens
- OAuth 2.0

**For Production**: Add authentication via API Gateway or custom middleware

---

## Endpoints

### Health Check

**Purpose**: Liveness probe - is the service alive?

#### `GET /health`

**Description**: Returns health status of the API and its dependencies

**Request**:
```http
GET /health HTTP/1.1
Host: localhost:8000
```

**Response** (200 OK):
```json
{
  "status": "healthy",
  "timestamp": "2026-02-13T10:30:45.123Z",
  "checks": {
    "api": "healthy",
    "redis": "healthy",
    "minio": "healthy"
  },
  "version": "1.0.0"
}
```

**Response** (503 Service Unavailable):
```json
{
  "status": "unhealthy",
  "timestamp": "2026-02-13T10:30:45.123Z",
  "checks": {
    "api": "healthy",
    "redis": "unhealthy",
    "minio": "healthy"
  },
  "errors": [
    "Redis connection failed: ConnectionRefusedError"
  ]
}
```

**Use Cases**:
- Kubernetes liveness probe
- Load balancer health checks
- Monitoring systems

---

### Readiness Check

**Purpose**: Readiness probe - can the service accept traffic?

#### `GET /ready`

**Description**: Returns readiness status (all systems operational)

**Request**:
```http
GET /ready HTTP/1.1
Host: localhost:8000
```

**Response** (200 OK):
```json
{
  "status": "ready",
  "timestamp": "2026-02-13T10:30:45.123Z",
  "checks": {
    "models_loaded": true,
    "redis_writable": true,
    "minio_writable": true
  }
}
```

**Response** (503 Service Unavailable):
```json
{
  "status": "not_ready",
  "timestamp": "2026-02-13T10:30:45.123Z",
  "checks": {
    "models_loaded": false,
    "redis_writable": true,
    "minio_writable": true
  },
  "errors": [
    "No models loaded yet, waiting for initial download"
  ]
}
```

**Use Cases**:
- Kubernetes readiness probe
- Rolling deployment coordination
- Traffic routing decisions

---

### Object Detection

**Purpose**: Detect objects in uploaded images using YOLO models

#### `POST /detect`

**Description**: Upload an image and get bounding boxes for detected objects

**Request**:
```http
POST /detect HTTP/1.1
Host: localhost:8000
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW

------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="file"; filename="image.jpg"
Content-Type: image/jpeg

<binary image data>
------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="model"

yolov8n
------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="confidence"

0.5
------WebKitFormBoundary7MA4YWxkTrZu0gW--
```

**Parameters**:

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `file` | File | Yes | - | Image file (JPEG, PNG, WebP, BMP) |
| `model` | String | No | `yolov8n` | Model variant: `yolov8n`, `yolov8s`, `yolov8m`, `yolov8l`, `yolov8x` |
| `confidence` | Float | No | `0.5` | Confidence threshold (0.0 - 1.0) |
| `iou` | Float | No | `0.45` | IoU threshold for NMS (0.0 - 1.0) |

**Response** (200 OK):
```json
{
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-02-13T10:30:45.123Z",
  "model": "yolov8n",
  "image_size": {
    "width": 1920,
    "height": 1080
  },
  "inference_time_ms": 52.3,
  "cached": false,
  "detections": [
    {
      "class": "person",
      "class_id": 0,
      "confidence": 0.92,
      "bbox": {
        "x1": 120,
        "y1": 200,
        "x2": 350,
        "y2": 680
      },
      "center": {
        "x": 235,
        "y": 440
      },
      "area": 110400
    },
    {
      "class": "car",
      "class_id": 2,
      "confidence": 0.87,
      "bbox": {
        "x1": 800,
        "y1": 400,
        "x2": 1200,
        "y2": 700
      },
      "center": {
        "x": 1000,
        "y": 550
      },
      "area": 120000
    }
  ],
  "detection_count": 2,
  "storage": {
    "input_url": "https://minio.vision-infra:9000/vision-uploads/550e8400.../image.jpg",
    "result_url": "https://minio.vision-infra:9000/vision-results/550e8400.../result.jpg"
  }
}
```

**Response Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `request_id` | String | Unique request identifier (UUID) |
| `timestamp` | String | ISO 8601 timestamp |
| `model` | String | Model used for inference |
| `image_size` | Object | Original image dimensions |
| `inference_time_ms` | Float | Inference duration in milliseconds |
| `cached` | Boolean | Whether result was from cache |
| `detections` | Array | List of detected objects |
| `detections[].class` | String | Object class name (e.g., "person", "car") |
| `detections[].class_id` | Integer | COCO class ID |
| `detections[].confidence` | Float | Detection confidence score (0.0 - 1.0) |
| `detections[].bbox` | Object | Bounding box coordinates |
| `detections[].bbox.x1` | Integer | Top-left X coordinate |
| `detections[].bbox.y1` | Integer | Top-left Y coordinate |
| `detections[].bbox.x2` | Integer | Bottom-right X coordinate |
| `detections[].bbox.y2` | Integer | Bottom-right Y coordinate |
| `detections[].center` | Object | Bounding box center point |
| `detections[].area` | Integer | Bounding box area in pixels |
| `detection_count` | Integer | Total number of detections |
| `storage` | Object | MinIO URLs for stored images |

**Supported Image Formats**:
- JPEG (.jpg, .jpeg)
- PNG (.png)
- WebP (.webp)
- BMP (.bmp)

**Image Size Limits**:
- Max file size: 10MB
- Max dimensions: 4096 x 4096 pixels
- Min dimensions: 32 x 32 pixels

---

### Metrics

**Purpose**: Prometheus metrics endpoint for monitoring

#### `GET /metrics`

**Description**: Returns metrics in Prometheus exposition format

**Request**:
```http
GET /metrics HTTP/1.1
Host: localhost:8000
```

**Response** (200 OK):
```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="POST",endpoint="/detect",status="200"} 1523.0
http_requests_total{method="GET",endpoint="/health",status="200"} 8932.0

# HELP inference_duration_seconds YOLO inference duration
# TYPE inference_duration_seconds histogram
inference_duration_seconds_bucket{model="yolov8n",le="0.05"} 1234.0
inference_duration_seconds_bucket{model="yolov8n",le="0.1"} 1450.0
inference_duration_seconds_bucket{model="yolov8n",le="0.5"} 1520.0
inference_duration_seconds_bucket{model="yolov8n",le="1.0"} 1523.0
inference_duration_seconds_bucket{model="yolov8n",le="+Inf"} 1523.0
inference_duration_seconds_sum{model="yolov8n"} 78.5
inference_duration_seconds_count{model="yolov8n"} 1523.0

# HELP cache_hits_total Cache hits
# TYPE cache_hits_total counter
cache_hits_total 892.0

# HELP cache_misses_total Cache misses
# TYPE cache_misses_total counter
cache_misses_total 631.0

# HELP active_models_count Number of models in LRU cache
# TYPE active_models_count gauge
active_models_count 2.0
```

**Metrics Exposed**:

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `http_requests_total` | Counter | `method`, `endpoint`, `status` | Total HTTP requests |
| `inference_duration_seconds` | Histogram | `model` | Inference time distribution |
| `model_load_duration_seconds` | Histogram | `model` | Model loading time |
| `cache_hits_total` | Counter | - | Redis cache hits |
| `cache_misses_total` | Counter | - | Redis cache misses |
| `active_models_count` | Gauge | - | Models in memory |

**Use Cases**:
- Prometheus scraping
- Grafana dashboards
- Alert rule evaluation

---

## Request/Response Formats

### Content-Type

**Requests**:
- `/detect`: `multipart/form-data` (file upload)
- All others: `application/json`

**Responses**:
- All endpoints: `application/json` (except `/metrics` which is `text/plain`)

### Character Encoding

All text: **UTF-8**

### Date/Time Format

ISO 8601: `YYYY-MM-DDTHH:mm:ss.sssZ`

Example: `2026-02-13T10:30:45.123Z`

---

## Error Handling

### Error Response Format

```json
{
  "error": {
    "code": "INVALID_IMAGE_FORMAT",
    "message": "Unsupported image format. Supported: JPEG, PNG, WebP, BMP",
    "details": {
      "received_format": "GIF",
      "supported_formats": ["JPEG", "PNG", "WebP", "BMP"]
    }
  },
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-02-13T10:30:45.123Z"
}
```

### HTTP Status Codes

| Code | Meaning | When Used |
|------|---------|-----------|
| `200` | OK | Successful request |
| `400` | Bad Request | Invalid input (missing file, bad format, etc.) |
| `413` | Payload Too Large | Image exceeds 10MB limit |
| `422` | Unprocessable Entity | Valid format but can't be processed |
| `429` | Too Many Requests | Rate limit exceeded |
| `500` | Internal Server Error | Unexpected server error |
| `503` | Service Unavailable | Service unhealthy (Redis/MinIO down) |

### Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `MISSING_FILE` | 400 | No file uploaded |
| `INVALID_IMAGE_FORMAT` | 400 | Unsupported image format |
| `IMAGE_TOO_LARGE` | 413 | File size > 10MB |
| `IMAGE_DIMENSIONS_INVALID` | 400 | Image too small or too large |
| `INVALID_MODEL` | 400 | Model not in [yolov8n, yolov8s, yolov8m, yolov8l, yolov8x] |
| `INVALID_CONFIDENCE` | 400 | Confidence not in range [0.0, 1.0] |
| `MODEL_LOAD_FAILED` | 500 | Failed to load YOLO model |
| `INFERENCE_FAILED` | 500 | Error during object detection |
| `STORAGE_ERROR` | 500 | Failed to store image in MinIO |
| `CACHE_ERROR` | 500 | Redis operation failed (non-critical) |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests from this IP |
| `SERVICE_UNAVAILABLE` | 503 | Redis or MinIO unavailable |

### Example Error Responses

**Missing File**:
```json
{
  "error": {
    "code": "MISSING_FILE",
    "message": "No file uploaded. Please provide an image file in the 'file' field."
  },
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-02-13T10:30:45.123Z"
}
```

**Invalid Model**:
```json
{
  "error": {
    "code": "INVALID_MODEL",
    "message": "Invalid model 'yolov9'. Supported models: yolov8n, yolov8s, yolov8m, yolov8l, yolov8x",
    "details": {
      "received": "yolov9",
      "supported": ["yolov8n", "yolov8s", "yolov8m", "yolov8l", "yolov8x"]
    }
  },
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-02-13T10:30:45.123Z"
}
```

**Image Too Large**:
```json
{
  "error": {
    "code": "IMAGE_TOO_LARGE",
    "message": "Image size exceeds 10MB limit",
    "details": {
      "size_bytes": 12582912,
      "max_bytes": 10485760
    }
  },
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-02-13T10:30:45.123Z"
}
```

---

## Rate Limiting

### Current Implementation

**Local/Dev**: No rate limiting

**Production** (via CDN WAF):
- **AWS CloudFront**: 2000 requests/min per IP
- **Azure Front Door**: 100 requests/min per IP

### Headers (Future)

```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 987
X-RateLimit-Reset: 1612345678
```

### Rate Limit Exceeded Response

```json
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Rate limit exceeded. Max 1000 requests per minute.",
    "details": {
      "limit": 1000,
      "window": "1 minute",
      "retry_after": 45
    }
  },
  "request_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2026-02-13T10:30:45.123Z"
}
```

---

## Examples

### cURL

**Basic Detection (YOLOv8n)**:
```bash
curl -X POST http://localhost:8000/detect \
  -F "file=@path/to/image.jpg" \
  -F "model=yolov8n"
```

**Detection with Custom Confidence**:
```bash
curl -X POST http://localhost:8000/detect \
  -F "file=@image.jpg" \
  -F "model=yolov8m" \
  -F "confidence=0.7"
```

**Pretty-Print JSON**:
```bash
curl -X POST http://localhost:8000/detect \
  -F "file=@image.jpg" | jq '.'
```

**Save Result Image**:
```bash
# Get result URL from response
RESULT_URL=$(curl -X POST http://localhost:8000/detect \
  -F "file=@image.jpg" | jq -r '.storage.result_url')

# Download result image
curl "$RESULT_URL" -o result_with_boxes.jpg
```

### Python (requests)

```python
import requests

# Upload image
url = "http://localhost:8000/detect"
files = {"file": open("image.jpg", "rb")}
data = {
    "model": "yolov8n",
    "confidence": 0.5
}

response = requests.post(url, files=files, data=data)

# Check response
if response.status_code == 200:
    result = response.json()
    print(f"Found {result['detection_count']} objects")
    
    for detection in result['detections']:
        print(f"{detection['class']}: {detection['confidence']:.2f}")
else:
    print(f"Error: {response.json()}")
```

### Python (aiohttp - async)

```python
import aiohttp
import asyncio

async def detect_objects(image_path: str):
    url = "http://localhost:8000/detect"
    
    async with aiohttp.ClientSession() as session:
        data = aiohttp.FormData()
        data.add_field('file', 
                      open(image_path, 'rb'), 
                      filename='image.jpg',
                      content_type='image/jpeg')
        data.add_field('model', 'yolov8n')
        
        async with session.post(url, data=data) as resp:
            if resp.status == 200:
                result = await resp.json()
                return result
            else:
                error = await resp.json()
                raise Exception(f"API Error: {error}")

# Run
result = asyncio.run(detect_objects("image.jpg"))
print(result)
```

### JavaScript (Fetch API)

```javascript
async function detectObjects(file) {
  const url = "http://localhost:8000/detect";
  
  const formData = new FormData();
  formData.append("file", file);
  formData.append("model", "yolov8n");
  formData.append("confidence", "0.5");
  
  try {
    const response = await fetch(url, {
      method: "POST",
      body: formData
    });
    
    if (response.ok) {
      const result = await response.json();
      console.log(`Found ${result.detection_count} objects`);
      return result;
    } else {
      const error = await response.json();
      throw new Error(`API Error: ${error.error.message}`);
    }
  } catch (error) {
    console.error("Request failed:", error);
  }
}

// Usage with file input
const fileInput = document.getElementById('imageInput');
fileInput.addEventListener('change', async (e) => {
  const file = e.target.files[0];
  const result = await detectObjects(file);
  // Render results...
});
```

### React Hook

```javascript
import { useState } from 'react';

function useObjectDetection() {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  
  const detect = async (file, model = 'yolov8n') => {
    setLoading(true);
    setError(null);
    
    try {
      const formData = new FormData();
      formData.append('file', file);
      formData.append('model', model);
      
      const response = await fetch('http://localhost:8000/detect', {
        method: 'POST',
        body: formData
      });
      
      if (response.ok) {
        const data = await response.json();
        setResult(data);
      } else {
        const error = await response.json();
        setError(error.error.message);
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };
  
  return { detect, loading, result, error };
}

// Usage
function DetectionComponent() {
  const { detect, loading, result, error } = useObjectDetection();
  
  const handleFileChange = (e) => {
    const file = e.target.files[0];
    detect(file, 'yolov8n');
  };
  
  return (
    <div>
      <input type="file" onChange={handleFileChange} />
      {loading && <p>Detecting objects...</p>}
      {error && <p>Error: {error}</p>}
      {result && (
        <p>Found {result.detection_count} objects in {result.inference_time_ms}ms</p>
      )}
    </div>
  );
}
```

---

## SDKs & Client Libraries

### Future Official SDKs

- [ ] Python SDK (`pip install visionops-client`)
- [ ] JavaScript SDK (`npm install @visionops/client`)
- [ ] Go SDK (`go get github.com/astitvaveergarg/visionops-go`)
- [ ] Java SDK (Maven/Gradle)

### Community Contributions Welcome!

Interested in building an SDK? See [CONTRIBUTING.md](../CONTRIBUTING.md)

---

## API Versioning

**Current Version**: v1 (implicit in base path)

**Future Versions**:
- v2: `/v2/detect` (when breaking changes introduced)
- Deprecation notice: 6 months before v1 sunset

**Version Header** (future):
```http
X-API-Version: 1.0.0
```

---

## CORS Policy

**Development**: Permissive (all origins)

**Production**: Restricted to whitelisted domains

```http
Access-Control-Allow-Origin: https://yourdomain.com
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

---

## Webhooks (Future)

**Coming Soon**: Async detection with webhook callbacks

```json
{
  "url": "http://localhost:8000/detect",
  "method": "POST",
  "body": {
    "file": "<image>",
    "model": "yolov8n",
    "webhook_url": "https://yourapp.com/webhook"
  }
}
```

**Webhook Payload**:
```json
{
  "event": "detection.completed",
  "request_id": "550e8400...",
  "result": { ... }
}
```

---

## Performance Considerations

### Latency

**Expected Latency** (p95):
- YOLOv8n: 100-150ms (cached: 50ms)
- YOLOv8s: 150-200ms
- YOLOv8m: 250-350ms
- YOLOv8l: 400-500ms
- YOLOv8x: 600-800ms

**Factors**:
- Network latency: 10-50ms
- Model loading (first request): +2-30s
- Image size: Larger images = slower inference
- Concurrent requests: May queue if all pods busy

### Optimization Tips

1. **Use Smaller Models**: YOLOv8n for real-time, YOLOv8x for accuracy
2. **Resize Large Images**: Inference time scales with resolution
3. **Batch Requests**: (Future) Send multiple images in one request
4. **Cache Aware**: Identical images = instant results
5. **CDN Proximity**: Choose closest AWS region / Azure location

---

## Support & Contact

**Issues**: [GitHub Issues](https://github.com/astitvaveergarg/Vision-AI/issues)  
**Questions**: [GitHub Discussions](https://github.com/astitvaveergarg/Vision-AI/discussions)  
**Author**: Astitva Veer Garg ([@astitvaveergarg](https://github.com/astitvaveergarg))

---

**Last Updated**: February 13, 2026  
**API Version**: 1.0.0
