"""
Simple server to serve VisionOps frontend
"""
import uvicorn
from fastapi import FastAPI
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
import os

app = FastAPI(title="VisionOps Frontend")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Get the directory of this script
current_dir = os.path.dirname(os.path.abspath(__file__))

@app.get("/")
async def root():
    """Serve the main index.html"""
    return FileResponse(os.path.join(current_dir, "index.html"))

@app.get("/app.js")
async def get_js():
    """Serve app.js"""
    return FileResponse(os.path.join(current_dir, "app.js"), media_type="application/javascript")

@app.get("/{file_path:path}")
async def serve_file(file_path: str):
    """Serve other static files"""
    file_full_path = os.path.join(current_dir, file_path)
    if os.path.exists(file_full_path) and os.path.isfile(file_full_path):
        return FileResponse(file_full_path)
    return HTMLResponse(content="Not Found", status_code=404)

if __name__ == "__main__":
    uvicorn.run(
        "server:app",
        host="0.0.0.0",
        port=3000,
        reload=True
    )
