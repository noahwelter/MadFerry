"""Vision/text LLM extraction of schedules into the season JSON format.

Uses any OpenAI-compatible chat completions endpoint. Defaults to Google Gemini's OpenAI-compatible
API; set LLM_API_KEY (and optionally LLM_BASE_URL / LLM_MODEL to switch provider or model).
"""

import base64
import datetime as dt
import json
import os
import re
import urllib.error
import urllib.request
from typing import Dict

FORMAT = """Return ONLY a JSON object with this exact shape:
{
  "kind": "ferry" | "windsled",
  "label": short human label, e.g. "Sept 8 – Nov 1",
  "startDate": "YYYY-MM-DD" or null,
  "endDate": "YYYY-MM-DD" or null,          // null if open-ended (e.g. "until heavy ice")
  "endNote": string or null,                 // e.g. "Until heavy ice" when endDate is null
  "notes": [string],                         // footnotes such as "Schedule depends on weather and ice."
  "departures": [
    {"from": "bayfield" | "lapointe",        // "TO ISLAND" / "Leave BAYFIELD" => "bayfield"; "TO BAYFIELD" / "Leave MADELINE ISLAND" => "lapointe"
     "time": "HH:MM",                        // 24-hour local time
     "days": [1,2,3,4,5,6,7],                // ISO weekdays, Mon=1 ... Sun=7, sorted
     "note": string or null,
     "restricted": true | false}             // true only if the trip is not open to the public (e.g. school kids only)
  ]
}"""

FERRY_PROMPT = """You transcribe Madeline Island Ferry Line schedule images into JSON with perfect accuracy.

How to read the image:
- Left panel "TO ISLAND" departs Bayfield. Right panel "TO BAYFIELD" departs La Pointe (Madeline Island).
- The middle "DATE" column gives the date range. Context for the year is provided below.
- Black times run every day ("DAILY"). Red times are restricted: a red label such as "Mon-Fri only",
  "Mon-Th only", "Th-Sat only" or "Fri only" applies to every red time directly below it, up to the next
  red label or a black time. Read each column top-to-bottom, left column first.
- "Mon-Th" means Monday through Thursday. Ranges are inclusive.
- Include every single time exactly once. Do not invent times. Treat "7.30 PM" as 19:30.
- kind is "ferry".

""" + FORMAT

WINDSLED_PROMPT = """You transcribe the Madeline Island windsled & van winter schedule text into JSON.
- "Leave MADELINE ISLAND" => from "lapointe"; "Leave BAYFIELD" => from "bayfield".
- Merge identical times across day groups into a single departure with combined days.
- If the same time is listed both as a public trip and as "School Kids only", keep only the public one.
- Trips only for school kids are restricted=true with note "School kids only (if school in session)".
- "12Noon" is 12:00. kind is "windsled"; startDate/endDate are null; endNote null; label "Windsled & van".
- Put general warnings (e.g. schedule may change, hotline numbers) in notes.

""" + FORMAT


def _config():
    base = os.environ.get("LLM_BASE_URL") or "https://generativelanguage.googleapis.com/v1beta/openai"
    key = os.environ.get("LLM_API_KEY")
    model = os.environ.get("LLM_MODEL") or "gemini-3.8-flash"
    if not key:
        raise RuntimeError("Set LLM_API_KEY to run extraction")
    return base, key, model


def _chat(messages) -> Dict:
    base, key, model = _config()
    body = json.dumps(
        {"model": model, "temperature": 0, "response_format": {"type": "json_object"}, "messages": messages}
    ).encode()
    req = urllib.request.Request(
        f"{base}/chat/completions",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    req.add_header("Authorization", "Bearer " + key)
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            payload = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"LLM HTTP {exc.code}: {exc.read()[:500]!r}") from exc
    content = payload["choices"][0]["message"]["content"].strip()
    content = re.sub(r"^```(?:json)?\s*|\s*```$", "", content)
    return json.loads(content)


def extract_ferry_image(image: bytes, title: str, page_title: str, today: dt.date) -> Dict:
    context = (
        f"Context: page title {page_title!r}; image title {title!r}; today is {today.isoformat()}. "
        "Take the date range from the image itself, not from the image title. If the image has no year, "
        "use the year in the page title, otherwise the year that puts the range closest to today. "
        "If a range crosses New Year, the end date is in the following year."
    )
    data_url = "data:image/jpeg;base64," + base64.b64encode(image).decode()
    return _chat(
        [
            {"role": "system", "content": FERRY_PROMPT},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": context},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            },
        ]
    )


def extract_windsled_text(text: str) -> Dict:
    return _chat([{"role": "system", "content": WINDSLED_PROMPT}, {"role": "user", "content": text}])
