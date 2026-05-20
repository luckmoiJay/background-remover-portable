import base64
import io
import logging
from dataclasses import dataclass

import numpy as np
from flask import Flask, jsonify, render_template, request
from PIL import Image, ImageFilter, ImageOps
from werkzeug.exceptions import HTTPException

try:
    from rembg import new_session, remove
except Exception:
    new_session = None
    remove = None


app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 24 * 1024 * 1024

logging.basicConfig(
    filename="app.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    encoding="utf-8",
)

REMBG_SESSION = None


@dataclass
class RemoveOptions:
    alpha_matting: bool
    foreground_threshold: int
    background_threshold: int
    erode_size: int
    feather: int
    sharpen: int
    trim: bool


def _session():
    global REMBG_SESSION
    if remove is None or new_session is None:
        return None
    if REMBG_SESSION is None:
        REMBG_SESSION = new_session("u2net")
    return REMBG_SESSION


def _image_to_png_bytes(image: Image.Image) -> bytes:
    out = io.BytesIO()
    image.save(out, format="PNG", optimize=True)
    return out.getvalue()


def _b64_png(image: Image.Image) -> str:
    return base64.b64encode(_image_to_png_bytes(image)).decode("ascii")


def _open_image(file_storage) -> Image.Image:
    raw = file_storage.read()
    if not raw:
        raise ValueError("No image file was received.")
    image = Image.open(io.BytesIO(raw))
    ImageOps.exif_transpose(image, in_place=True)
    return image.convert("RGBA")


def _trim_transparent(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if not bbox:
        return image
    return image.crop(bbox)


def _fallback_remove(image: Image.Image, feather: int) -> Image.Image:
    rgb = np.asarray(image.convert("RGB")).astype(np.float32)
    h, w, _ = rgb.shape
    border = max(2, min(h, w) // 32)
    samples = np.concatenate(
        [
            rgb[:border, :, :].reshape(-1, 3),
            rgb[-border:, :, :].reshape(-1, 3),
            rgb[:, :border, :].reshape(-1, 3),
            rgb[:, -border:, :].reshape(-1, 3),
        ],
        axis=0,
    )
    bg = np.median(samples, axis=0)
    distance = np.linalg.norm(rgb - bg, axis=2)
    border_distance = np.linalg.norm(samples - bg, axis=1)
    low = max(16.0, float(np.percentile(border_distance, 82)) + 12.0)
    high = max(low + 24.0, low * 2.4)
    alpha = ((distance - low) / (high - low) * 255.0).clip(0, 255).astype(np.uint8)
    mask = Image.fromarray(alpha, mode="L")
    mask = mask.filter(ImageFilter.MedianFilter(size=5))
    if feather > 0:
        mask = mask.filter(ImageFilter.GaussianBlur(radius=feather))
    result = image.copy()
    result.putalpha(mask)
    return result


def _apply_sharpen(image: Image.Image, sharpen: int) -> Image.Image:
    if sharpen <= 0:
        return image
    image = image.convert("RGBA")
    alpha = image.getchannel("A")
    rgb = image.convert("RGB")
    # Unsharp mask sharpens visible pixels while the original alpha stays clean.
    sharpened = rgb.filter(ImageFilter.UnsharpMask(radius=1.2, percent=sharpen, threshold=3))
    result = sharpened.convert("RGBA")
    result.putalpha(alpha)
    return result


def _postprocess(image: Image.Image, options: RemoveOptions) -> Image.Image:
    image = image.convert("RGBA")
    if options.feather > 0:
        alpha = image.getchannel("A").filter(ImageFilter.GaussianBlur(radius=options.feather / 2))
        image.putalpha(alpha)
    image = _apply_sharpen(image, options.sharpen)
    if options.trim:
        image = _trim_transparent(image)
    return image


def remove_background(image: Image.Image, options: RemoveOptions) -> tuple[Image.Image, str]:
    source_bytes = _image_to_png_bytes(image)
    session = _session()
    if session is not None:
        result_bytes = remove(
            source_bytes,
            session=session,
            alpha_matting=options.alpha_matting,
            alpha_matting_foreground_threshold=options.foreground_threshold,
            alpha_matting_background_threshold=options.background_threshold,
            alpha_matting_erode_size=options.erode_size,
        )
        result = Image.open(io.BytesIO(result_bytes)).convert("RGBA")
        engine = "rembg/u2net"
    else:
        result = _fallback_remove(image, options.feather)
        engine = "local-border-sampler"
    return _postprocess(result, options), engine


def _parse_bool(value, default=False):
    if value is None:
        return default
    return str(value).lower() in {"1", "true", "yes", "on"}


def _clamp_int(value, default, low, high):
    try:
        number = int(value)
    except (TypeError, ValueError):
        return default
    return max(low, min(high, number))


@app.get("/")
def index():
    return render_template("index.html")


@app.get("/health")
def health():
    return jsonify({"ok": True, "rembg": remove is not None})


@app.errorhandler(Exception)
def handle_exception(exc):
    if isinstance(exc, HTTPException):
        return exc
    app.logger.exception("Unhandled server error")
    return (
        "Internal Server Error. Please check app.log in the app folder for details.",
        500,
    )


@app.post("/api/remove")
def api_remove():
    if "image" not in request.files:
        return jsonify({"error": "Please upload or paste an image first."}), 400
    try:
        image = _open_image(request.files["image"])
        options = RemoveOptions(
            alpha_matting=_parse_bool(request.form.get("alphaMatting"), True),
            foreground_threshold=_clamp_int(request.form.get("foregroundThreshold"), 240, 1, 255),
            background_threshold=_clamp_int(request.form.get("backgroundThreshold"), 10, 1, 255),
            erode_size=_clamp_int(request.form.get("erodeSize"), 10, 0, 32),
            feather=_clamp_int(request.form.get("feather"), 1, 0, 8),
            sharpen=_clamp_int(request.form.get("sharpen"), 25, 0, 220),
            trim=_parse_bool(request.form.get("trim"), True),
        )
        result, engine = remove_background(image, options)
        return jsonify(
            {
                "image": f"data:image/png;base64,{_b64_png(result)}",
                "width": result.width,
                "height": result.height,
                "engine": engine,
            }
        )
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
