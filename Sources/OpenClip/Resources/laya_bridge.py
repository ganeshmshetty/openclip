#!/usr/bin/env python3
"""OpenClip <-> Laya bridge.

OpenClip launches this script inside the Python environment it manages under ~/.openclip/laya
(see LayaRuntime.swift). One Laya checkpoint stays resident; requests and replies are JSON
lines on stdin/stdout so a decision costs one forward pass instead of a model load.

Protocol (one JSON object per line):

  -> {"op": "decide", "id": 1, "request": {"state": "...", "questions": [...], "tool_id": "..."}}
  <- {"id": 1, "response": {"answers": [...], "confidence": 0.9, "latency_ms": 35, ...}}
  <- {"id": 1, "error": "..."}
  -> {"op": "ping", "id": 2}           <- {"id": 2, "pong": true, "model": "english", "device": "mps"}
  -> {"op": "shutdown"}

  Unsolicited lines carry an "event": "status" (with a "phase") while importing, downloading and
  loading, then "ready" once decisions can be served.

The request is OpenClip's `DecisionQuestionPacker` wire format (questions as a list with id, type,
prompt, options, min, max) and the response is what `DecisionResponseParser` reads (answers as a
list with id plus noul / choice / score, confidence and probabilities). Only this file knows Laya's
own schema (questions keyed by id with instructions and criteria).

Flags:
  --model english|multilingual|typed-decisions   checkpoint to load (default english)
  --device cpu|mps|cuda                          override Laya's automatic device choice
  --warmup                                       download + load + one inference, then exit
  --selftest                                     exercise the schema mapping without a model
"""
import argparse
import glob
import json
import os
import sys
import time

# Everything the ML stack prints must stay off the protocol channel: keep a private handle to the
# real stdout and send Python's own stdout to stderr, which OpenClip writes to bridge.log.
_PROTOCOL_OUT = os.fdopen(os.dup(1), "w", encoding="utf-8")
sys.stdout = sys.stderr

MODELS = {
    "english": ("convaiinnovations/laya", None),
    "multilingual": ("convaiinnovations/laya", "multilingual"),
    "typed-decisions": ("convaiinnovations/laya", "typed-decisions"),
}
MAX_SCORE_LEVELS = 10  # System One score questions take 2-10 rubric levels.
PLACEHOLDER_CHOICES = ["A", "B", "C"]


def emit(obj):
    _PROTOCOL_OUT.write(json.dumps(obj, ensure_ascii=False) + "\n")
    _PROTOCOL_OUT.flush()


def log(message):
    sys.stderr.write("[laya-bridge] %s\n" % message)
    sys.stderr.flush()


# --- Schema mapping -------------------------------------------------------------------------


def to_laya_questions(questions):
    """OpenClip question list -> (Laya questions dict, per-question decode metadata)."""
    laya_questions = {}
    meta = {}
    for index, q in enumerate(questions or []):
        qid = str(q.get("id") or "q%d" % index)
        kind = q.get("type") or "noul"
        prompt = str(q.get("prompt") or "").strip() or "Judge the selection."
        if kind == "choice":
            options = []
            for option in q.get("options") or []:
                label = str(option).strip()
                if label and label not in options:
                    options.append(label)
            if len(options) < 2:
                options = list(PLACEHOLDER_CHOICES)
            laya_questions[qid] = {
                "type": "choice",
                "instructions": prompt,
                # OpenClip stores labels only; Laya accepts a label -> description map.
                "criteria": {label: label for label in options},
            }
            meta[qid] = {"type": "choice", "options": options}
        elif kind == "score":
            low = int(q.get("min", 1))
            high = int(q.get("max", 5))
            if high < low:
                low, high = high, low
            if high - low + 1 > MAX_SCORE_LEVELS:
                high = low + MAX_SCORE_LEVELS - 1
            if high == low:
                high = low + 1
            levels = list(range(low, high + 1))
            laya_questions[qid] = {
                "type": "score",
                "instructions": prompt,
                "criteria": [_score_label(n, low, high) for n in levels],
            }
            meta[qid] = {"type": "score", "levels": levels}
        else:
            laya_questions[qid] = {"type": "noul", "instructions": prompt}
            meta[qid] = {"type": "noul"}
    return laya_questions, meta


def _score_label(n, low, high):
    if n == low:
        return "%d (lowest)" % n
    if n == high:
        return "%d (highest)" % n
    return str(n)


def from_laya_answers(result, meta):
    """Laya result dict -> OpenClip response dict (DecisionResponseParser wire format)."""
    answers = []
    for qid, answer in (result.get("answers") or {}).items():
        info = meta.get(qid) or {"type": answer.get("type")}
        confidence = answer.get("confidence")
        kind = info.get("type")
        if kind == "choice":
            answers.append({
                "id": qid,
                "type": "choice",
                "choice": answer.get("choice"),
                "confidence": confidence,
                "probabilities": answer.get("probabilities") or {},
            })
        elif kind == "score":
            levels = info.get("levels") or []
            probabilities = answer.get("probabilities") or {}
            if levels and probabilities:
                best = max(range(len(levels)), key=lambda i: float(probabilities.get(str(i), 0.0)))
            elif levels:
                best = int(round(float(answer.get("score") or 0.0)))
            else:
                best = 0
            best = max(0, min(len(levels) - 1, best)) if levels else best
            value = levels[best] if levels else best
            answers.append({
                "id": qid,
                "type": "score",
                "score": int(value),
                # Laya's expected value over the rubric, kept for callers that want the mean.
                "expected": answer.get("score"),
                "confidence": confidence,
                "probabilities": {
                    str(levels[i]): float(probabilities.get(str(i), 0.0)) for i in range(len(levels))
                },
            })
        else:
            p_true = float(answer.get("noul") or 0.0)
            answers.append({
                "id": qid,
                "type": "noul",
                "noul": p_true >= 0.5,
                "confidence": confidence,
                "probabilities": {"true": round(p_true, 4), "false": round(1.0 - p_true, 4)},
            })
    confidences = [a["confidence"] for a in answers if a.get("confidence") is not None]
    return {
        "answers": answers,
        "confidence": min(confidences) if confidences else None,
        "model": result.get("model"),
        "usage": result.get("usage"),
    }


# --- Model lifecycle ------------------------------------------------------------------------


def snapshot_is_cached(repo, subfolder):
    """True when the checkpoint is already in the Hugging Face cache (no download needed)."""
    hub = os.environ.get("HF_HUB_CACHE") or os.path.join(
        os.environ.get("HF_HOME", os.path.expanduser("~/.cache/huggingface")), "hub"
    )
    repo_dir = os.path.join(hub, "models--" + repo.replace("/", "--"), "snapshots", "*")
    parts = [repo_dir] + ([subfolder] if subfolder else []) + ["model.safetensors"]
    return bool(glob.glob(os.path.join(*parts)))


def load_agent(model_name, device):
    if model_name not in MODELS:
        raise ValueError("unknown model %r; expected one of %s" % (model_name, sorted(MODELS)))
    repo, subfolder = MODELS[model_name]
    emit({"event": "status", "phase": "importing", "model": model_name})
    started = time.time()
    import laya  # noqa: WPS433 (deferred: torch import is slow and only needed here)

    phase = "loading" if snapshot_is_cached(repo, subfolder) else "downloading"
    emit({"event": "status", "phase": phase, "model": model_name})
    agent = laya.load(repo, device=device, subfolder=subfolder)
    emit({
        "event": "ready",
        "model": model_name,
        "device": str(agent.device),
        "load_ms": int((time.time() - started) * 1000),
    })
    return agent


def decide(agent, request):
    state = request.get("state") or ""
    if not str(state).strip():
        raise ValueError("empty state")
    questions, meta = to_laya_questions(request.get("questions") or [])
    if not questions:
        raise ValueError("no questions")
    started = time.time()
    result = agent.system_one(state, questions)
    response = from_laya_answers(result, meta)
    response["latency_ms"] = int((time.time() - started) * 1000)
    response["device"] = str(getattr(agent, "device", ""))
    return response


def serve(agent, model_name):
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except ValueError:
            emit({"error": "malformed request line"})
            continue
        op = message.get("op")
        rid = message.get("id")
        if op == "shutdown":
            log("shutdown requested")
            return 0
        if op == "ping":
            emit({"id": rid, "pong": True, "model": model_name, "device": str(agent.device)})
            continue
        if op == "decide":
            try:
                emit({"id": rid, "response": decide(agent, message.get("request") or {})})
            except Exception as error:  # noqa: BLE001 (reported to the caller, never fatal)
                emit({"id": rid, "error": "%s: %s" % (type(error).__name__, error)})
            continue
        emit({"id": rid, "error": "unknown op %r" % op})
    log("stdin closed")
    return 0


# --- Self-test ------------------------------------------------------------------------------


class _FakeAgent:
    """Answers shaped exactly like laya.Agent.system_one, without a model."""

    device = "fake"

    def system_one(self, state, questions):
        answers = {}
        for qid, q in questions.items():
            if q["type"] == "choice":
                keys = list(q["criteria"].keys())
                answers[qid] = {"type": "choice", "choice": keys[-1], "confidence": 0.8,
                                "probabilities": {k: (0.8 if k == keys[-1] else 0.2 / (len(keys) - 1)) for k in keys}}
            elif q["type"] == "score":
                k = len(q["criteria"])
                answers[qid] = {"type": "score", "score": 1.4, "confidence": 0.6,
                                "probabilities": {str(i): (0.55 if i == 1 else 0.45 / (k - 1)) for i in range(k)}}
            else:
                answers[qid] = {"type": "noul", "noul": 0.91, "confidence": 0.91}
        return {"model": "fake", "answers": answers, "usage": {"input_tokens": 3, "output_tokens": 0}}


def selftest():
    agent = _FakeAgent()
    request = {
        "state": "Please wire the refund today, this is urgent.",
        "questions": [
            {"id": "safe", "type": "noul", "prompt": "Is this safe to share?"},
            {"id": "dept", "type": "choice", "prompt": "Which team?", "options": ["billing", "tech", "billing", " "]},
            {"id": "tone", "type": "score", "prompt": "How urgent?", "min": 1, "max": 5},
            {"id": "empty_choice", "type": "choice", "prompt": "Pick", "options": []},
        ],
    }
    response = decide(agent, request)
    by_id = {a["id"]: a for a in response["answers"]}
    checks = [
        by_id["safe"]["noul"] is True and by_id["safe"]["probabilities"]["true"] == 0.91,
        by_id["dept"]["choice"] == "tech" and set(by_id["dept"]["probabilities"]) == {"billing", "tech"},
        by_id["tone"]["score"] == 2 and set(by_id["tone"]["probabilities"]) == {"1", "2", "3", "4", "5"},
        by_id["empty_choice"]["choice"] == PLACEHOLDER_CHOICES[-1],
        response["confidence"] == 0.6,
        to_laya_questions([{"id": "s", "type": "score", "min": 0, "max": 100}])[0]["s"]["criteria"].__len__() == MAX_SCORE_LEVELS,
    ]
    ok = all(checks)
    emit({"event": "selftest", "ok": ok, "checks": checks, "response": response})
    return 0 if ok else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", default="english", choices=sorted(MODELS))
    parser.add_argument("--device", default=None)
    parser.add_argument("--warmup", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()

    if args.selftest:
        return selftest()

    try:
        agent = load_agent(args.model, args.device)
    except Exception as error:  # noqa: BLE001
        emit({"event": "fatal", "error": "%s: %s" % (type(error).__name__, error)})
        log("load failed: %r" % (error,))
        return 2

    if args.warmup:
        started = time.time()
        decide(agent, {"state": "hello there", "questions": [{"id": "greeting", "type": "noul", "prompt": "Is this a greeting?"}]})
        emit({"event": "warm", "model": args.model, "device": str(agent.device), "first_ms": int((time.time() - started) * 1000)})
        return 0

    return serve(agent, args.model)


if __name__ == "__main__":
    sys.exit(main())
