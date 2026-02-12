# VisionOps API Documentation

## Base URL

**Local Development:**
```
http://localhost:8000
```

**Kubernetes (Port Forward):**
```
http://localhost:8000
```

**Production:**
```
https://api.vision.example.com
```

## Interactive Docs

FastAPI provides automatic interactive API documentation:

- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

---

## Endpoints

### 1. Health Check

**GET** `/`

Returns basic service information.

**Response:**
```json
{
  "service": "VisionOps API",
  "status": "healthy",
  "version": "1.0.0"
}
```

**Example:**
```bash
curl http://localhost:8000/
```

---

### 2. Detailed Health Check

**GET** `/health`

Returns detailed health status of all dependencies.

**Response:**
```json
{
  "status": "healthy",
  "redis": "healthy",
  "minio": "healthy",
  "model": "loaded"
}
```

**Status Codes:**
- `200 OK` - All services healthy
- `503 Service Unavailable` - One or more services unhealthy

**Example:**
```bash
curl http://localhost:8000/health
```

---

### 3. Object Detection

**POST** `/detect`

Detect objects in an uploaded image.

**Request:**
- **Content-Type**: `multipart/form-data`
- **Body**: Form field `file` with image data

**Supported Formats:**
- JPEG/JPG
- PNG
- BMP
- TIFF

**Max File Size:** 10 MB

**Response:**
```json
{
  "filename": "test_image.jpg",
  "image_hash": "a3f2b9c8...",
  "cached": false,
  "detections": [
    {
      "class": "person",
      "confidence": 0.89,
      "bbox": [245, 120, 380, 450]
    },
    {
      "class": "dog",
      "confidence": 0.76,
      "bbox": [100, 200, 250, 400]
    }
  ],
  "inference_time_ms": 1234,
  "total_time_ms": 1250
}
```

**Status Codes:**
- `200 OK` - Success
- `400 Bad Request` - Invalid image format
- `413 Payload Too Large` - File too large
- `500 Internal Server Error` - Processing error

**Example (curl):**
```bash
curl -X POST http://localhost:8000/detect \
  -F "file=@test_image.jpg"
```

**Example (Python):**
```python
import requests

url = "http://localhost:8000/detect"
files = {"file": open("test_image.jpg", "rb")}

response = requests.post(url, files=files)
print(response.json())
```

**Example (JavaScript):**
```javascript
const formData = new FormData();
formData.append('file', fileInput.files[0]);

fetch('http://localhost:8000/detect', {
  method: 'POST',
  body: formData
})
.then(res => res.json())
.then(data => console.log(data));
```

---

### 4. Metrics (Prometheus)

**GET** `/metrics`

Returns Prometheus-formatted metrics.

**Response:**
```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="POST",endpoint="/detect",status="200"} 1234

# HELP inference_duration_seconds Inference duration
# TYPE inference_duration_seconds histogram
inference_duration_seconds_bucket{le="0.5"} 500
inference_duration_seconds_bucket{le="1.0"} 800
inference_duration_seconds_bucket{le="2.0"} 950
```

**Example:**
```bash
curl http://localhost:8000/metrics
```

---

## Response Format

### Success Response
```json
{
  "filename": "string",
  "image_hash": "string",
  "cached": boolean,
  "detections": [
    {
      "class": "string",
      "confidence": float,
      "bbox": [x1, y1, x2, y2]
    }
  ],
  "inference_time_ms": integer,
  "total_time_ms": integer
}
```

### Error Response
```json
{
  "detail": "Error message",
  "error_code": "ERROR_CODE",
  "timestamp": "2026-02-12T10:30:00Z"
}
```

---

## Detection Classes

YOLOv8 can detect 80 COCO classes:

| Class ID | Class Name |
|----------|------------|
| 0 | person |
| 1 | bicycle |
| 2 | car |
| 3 | motorcycle |
| 4 | airplane |
| 5 | bus |
| 6 | train |
| 7 | truck |
| 8 | boat |
| ... | ... |

[Full COCO class list](https://github.com/ultralytics/ultralytics/blob/main/ultralytics/cfg/datasets/coco.yaml)

---

## Bounding Box Format

Bounding boxes use **absolute pixel coordinates**:

```
[x1, y1, x2, y2]
```

Where:
- `x1, y1` = top-left corner
- `x2, y2` = bottom-right corner

**Example:**
```json
{
  "bbox": [100, 200, 300, 400]
}
```

Means:
- Top-left: (100, 200)
- Bottom-right: (300, 400)
- Width: 200px
- Height: 200px

---

## Rate Limiting

**Current:** No rate limiting

**Future:** 100 requests/minute per API key

---

## Authentication

**Current:** No authentication

**Future:** Bearer token authentication

---

## Error Codes

| Status | Error Code | Description |
|--------|------------|-------------|
| 400 | `INVALID_IMAGE` | Image format not supported |
| 400 | `EMPTY_FILE` | No file uploaded |
| 413 | `FILE_TOO_LARGE` | File exceeds 10 MB |
| 500 | `INFERENCE_ERROR` | Model inference failed |
| 500 | `STORAGE_ERROR` | Failed to store image |
| 503 | `SERVICE_UNAVAILABLE` | Redis/MinIO unavailable |

---

## Caching Behavior

The API uses Redis for result caching:

1. **Cache Key:** SHA256 hash of image bytes
2. **TTL:** 3600 seconds (1 hour)
3. **Hit Rate:** Monitored via `/metrics`

**Benefits:**
- Identical images return instantly
- Reduces compute cost
- Improves response time 20x

**Example:**
```bash
# First request (cache miss)
time curl -X POST http://localhost:8000/detect -F "file=@test.jpg"
# Time: ~1500ms

# Second request (cache hit)
time curl -X POST http://localhost:8000/detect -F "file=@test.jpg"
# Time: ~50ms
```

---

## Performance Benchmarks

| Metric | Target | Achieved |
|--------|--------|----------|
| Cached response | < 100ms | TBD |
| Inference (small) | < 1s | TBD |
| Inference (large) | < 2s | TBD |
| Throughput | 100 req/s | TBD |

---

## Testing Examples

### Test with curl
```bash
# Health check
curl http://localhost:8000/health

# Detect objects
curl -X POST http://localhost:8000/detect \
  -F "file=@test_image.jpg" \
  | jq .
```

### Test with Python
```python
import requests

# Health check
response = requests.get("http://localhost:8000/health")
print(response.json())

# Detect objects
files = {"file": open("test_image.jpg", "rb")}
response = requests.post("http://localhost:8000/detect", files=files)
result = response.json()

for detection in result["detections"]:
    print(f"{detection['class']}: {detection['confidence']:.2f}")
```

### Test with PowerShell
```powershell
# Health check
Invoke-RestMethod -Uri "http://localhost:8000/health"

# Detect objects
$file = Get-Item "test_image.jpg"
$form = @{
    file = $file
}
Invoke-RestMethod -Uri "http://localhost:8000/detect" -Method Post -Form $form
```

---

## WebSocket Support (Future)

Real-time inference via WebSockets:

```javascript
const ws = new WebSocket('ws://localhost:8000/ws/detect');

ws.onopen = () => {
  ws.send(imageBlob);
};

ws.onmessage = (event) => {
  const result = JSON.parse(event.data);
  console.log(result.detections);
};
```

---

## Batch Processing (Future)

Process multiple images in one request:

**POST** `/detect/batch`

```json
{
  "images": [
    {"url": "s3://bucket/image1.jpg"},
    {"url": "s3://bucket/image2.jpg"}
  ]
}
```

---

**API Version:** 1.0  
**Last Updated:** February 12, 2026
