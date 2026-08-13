import json
import os
import tempfile
import threading
import uuid
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import PlainTextResponse
from paddleocr import PPStructureV3

app = FastAPI(title="RAGFlow local PP-StructureV3 adapter")
jobs: dict[str, dict] = {}
jobs_lock = threading.Lock()
pipeline = None
pipeline_lock = threading.Lock()


def get_pipeline():
    global pipeline
    with pipeline_lock:
        if pipeline is None:
            pipeline = PPStructureV3(device=os.getenv("OCR_DEVICE", "cpu"))
    return pipeline


def json_value(result):
    value = getattr(result, "json", result)
    if callable(value):
        value = value()
    return json.loads(json.dumps(value, default=lambda item: item.tolist() if hasattr(item, "tolist") else str(item)))


def run_job(job_id: str, source: Path):
    try:
        output = []
        for result in get_pipeline().predict(input=str(source)):
            value = json_value(result)
            if "layoutParsingResults" in value or "ocrResults" in value:
                payload = value
            else:
                pruned = value.get("res", value)
                markdown = getattr(result, "markdown", {}) or {}
                payload = {
                    "layoutParsingResults": [{
                        "prunedResult": pruned,
                        "markdown": {"text": markdown.get("markdown_texts", ""), "images": None},
                    }],
                    "ocrResults": [],
                }
            output.append({"result": payload})
        result_path = Path(tempfile.gettempdir()) / f"paddleocr-{job_id}.jsonl"
        result_path.write_text("\n".join(json.dumps(row, ensure_ascii=False) for row in output), encoding="utf-8")
        with jobs_lock:
            jobs[job_id] = {"state": "done", "path": result_path}
    except Exception as exc:
        with jobs_lock:
            jobs[job_id] = {"state": "failed", "error": str(exc)}
    finally:
        source.unlink(missing_ok=True)


@app.get("/health")
def health():
    return {"status": "ok", "model": os.getenv("OCR_MODEL", "PP-StructureV3"), "device": os.getenv("OCR_DEVICE", "cpu")}


@app.post("/api/v2/ocr/jobs")
async def create_job(model: str = Form(...), optionalPayload: str = Form("{}"), file: UploadFile = File(...)):
    if model != os.getenv("OCR_MODEL", "PP-StructureV3"):
        raise HTTPException(400, f"unsupported model: {model}")
    json.loads(optionalPayload)
    job_id = uuid.uuid4().hex
    suffix = Path(file.filename or "document.pdf").suffix
    source = Path(tempfile.gettempdir()) / f"paddleocr-{job_id}{suffix}"
    source.write_bytes(await file.read())
    with jobs_lock:
        jobs[job_id] = {"state": "running"}
    threading.Thread(target=run_job, args=(job_id, source), daemon=True).start()
    return {"data": {"jobId": job_id}}


@app.get("/api/v2/ocr/jobs/{job_id}")
def get_job(job_id: str):
    with jobs_lock:
        job = jobs.get(job_id)
    if not job:
        raise HTTPException(404, "job not found")
    data = {"state": job["state"]}
    if job["state"] == "done":
        data["resultJsonUrl"] = f"http://paddleocr:8080/api/v2/ocr/results/{job_id}"
    elif job["state"] == "failed":
        data["errorMsg"] = job["error"]
    return {"data": data}


@app.get("/api/v2/ocr/results/{job_id}", response_class=PlainTextResponse)
def get_result(job_id: str):
    with jobs_lock:
        job = jobs.get(job_id)
    if not job or job["state"] != "done":
        raise HTTPException(404, "result not found")
    return job["path"].read_text(encoding="utf-8")
