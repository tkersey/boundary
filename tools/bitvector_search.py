#!/usr/bin/env python3
"""Optional offline QF_BV search. Results never authorize compiler rewrites."""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

VERSION = "4.15.3"
OPS = {"integer_bit_xor": "bvxor", "integer_bit_and": "bvand", "integer_bit_or": "bvor", "integer_bit_not": "bvnot"}

def validate(source):
    if source.get("format") != "boundary-bitvectors/v1" or source.get("encoding_complete") is not True or source.get("evaluation") != "total-straight-line-eager" or source.get("input_domain") != "all-bit-patterns":
        raise ValueError("incomplete or unsupported extraction")
    if not re.fullmatch(r"[0-9a-f]{64}", source.get("image_identity", "")):
        raise ValueError("missing image identity")
    nodes = source["nodes"]
    if not nodes or len(nodes) > 136 or type(source["result"]) is not int or not 0 <= source["result"] < len(nodes):
        raise ValueError("invalid graph bounds")
    inputs = []
    for i, node in enumerate(nodes):
        if type(node["bits"]) is not int or node["bits"] not in (8, 16, 32, 64) or type(node["schema"]) is not int or node["schema"] < 0:
            raise ValueError("invalid type")
        op = node["opcode"]
        operands = node.get("operands", [])
        if op == "input":
            if operands or type(node["input"]) is not int or node["input"] != len(inputs) or len(inputs) >= 8:
                raise ValueError("invalid input identity")
            inputs.append(node)
        elif op == "constant":
            if operands or type(node["value"]) is not int or not 0 <= node["value"] < (1 << node["bits"]):
                raise ValueError("invalid constant")
        elif op in OPS:
            if len(operands) != (1 if op == "integer_bit_not" else 2):
                raise ValueError("invalid arity")
            for operand in operands:
                if type(operand) is not int or not 0 <= operand < i or (nodes[operand]["schema"], nodes[operand]["bits"]) != (node["schema"], node["bits"]):
                    raise ValueError("invalid version or operand type")
        else:
            raise ValueError("unsupported opcode")
    return inputs

def evaluate_source(source, inputs, width=None):
    """Independent concrete interpreter; does not consume generated SMT text."""
    values = []
    for node in source["nodes"]:
        bits = width or node["bits"]
        mask = (1 << bits) - 1
        op = node["opcode"]
        operands = [values[i] for i in node.get("operands", [])]
        if op == "input": value = inputs[node["input"]]
        elif op == "constant": value = node["value"]
        elif op == "integer_bit_xor": value = operands[0] ^ operands[1]
        elif op == "integer_bit_and": value = operands[0] & operands[1]
        elif op == "integer_bit_or": value = operands[0] | operands[1]
        elif op == "integer_bit_not": value = ~operands[0]
        else: raise ValueError("unsupported concrete source")
        values.append(value & mask)
    return values[source["result"]]

def evaluate_target(target, inputs, bits):
    tag = target[0]
    if tag == "arg": return inputs[target[1]] & ((1 << bits) - 1)
    if tag == "const": return target[1] & ((1 << bits) - 1)
    left = evaluate_target(target[1], inputs, bits)
    right = evaluate_target(target[2], inputs, bits)
    return {"xor": lambda: left ^ right, "and": lambda: left & right, "or": lambda: left | right}[tag]()

def candidates(source, limit):
    result = source["nodes"][source["result"]]
    leaves = [("arg", n["input"]) for n in source["nodes"] if n["opcode"] == "input" and (n["schema"], n["bits"]) == (result["schema"], result["bits"])]
    leaves += [("const", 0), ("const", 1), ("const", (1 << result["bits"]) - 1)]
    count = 0
    for target in itertools.chain(leaves, ((op, left, right) for op in ("xor", "and", "or") for left in leaves for right in leaves)):
        if count >= limit: break
        yield target
        count += 1

def source_smt(source):
    lines = ["(set-logic QF_BV)", "(set-option :produce-models true)"]
    for i, node in enumerate(source["nodes"]):
        bits, op = node["bits"], node["opcode"]
        if op == "input":
            lines.append(f"(declare-fun x{node['input']} () (_ BitVec {bits}))")
            value = f"x{node['input']}"
        elif op == "constant": value = f"(_ bv{node['value']} {bits})"
        else: value = f"({OPS[op]} {' '.join('s'+str(j) for j in node['operands'])})"
        lines.append(f"(define-fun s{i} () (_ BitVec {bits}) {value})")
    return lines

def target_smt(target, bits):
    if target[0] == "arg": return f"x{target[1]}"
    if target[0] == "const": return f"(_ bv{target[1]} {bits})"
    operator = {"xor": "bvxor", "and": "bvand", "or": "bvor"}[target[0]]
    return f"({operator} {target_smt(target[1], bits)} {target_smt(target[2], bits)})"

def query(source, target, timeout_ms):
    bits = source["nodes"][source["result"]]["bits"]
    return "\n".join(source_smt(source) + [f"(set-option :timeout {timeout_ms})", f"(assert (not (= s{source['result']} {target_smt(target, bits)})))", "(check-sat)"]) + "\n"

def classify(stdout, returncode=0, timed_out=False):
    if timed_out: return {"status": "not-proved", "reason": "timeout"}
    tokens = stdout.strip().splitlines()
    if returncode != 0 or not tokens or tokens[0] not in ("sat", "unsat", "unknown"):
        return {"status": "not-proved", "reason": "solver-error-or-incomplete-output"}
    if any(line.lstrip().startswith("(error") for line in tokens):
        return {"status": "not-proved", "reason": "solver-error"}
    if sum(line.strip() in ("sat", "unsat", "unknown") for line in tokens) != 1 or (tokens[0] != "sat" and len(tokens) != 1):
        return {"status": "not-proved", "reason": "inconsistent-or-unexpected-output"}
    if tokens[0] == "unknown": return {"status": "not-proved", "reason": "unknown"}
    return {"status": "equivalent" if tokens[0] == "unsat" else "counterexample-exists"}

def finite_counterexample(source, target):
    inputs = validate(source)
    if len(inputs) > 2: return {"status": "not-run", "reason": "bounded-exhaustive-domain"}
    for values in itertools.product(range(16), repeat=len(inputs)):
        if evaluate_source(source, values, 4) != evaluate_target(target, values, 4):
            actual_bits = source["nodes"][source["result"]]["bits"]
            left, right = evaluate_source(source, values), evaluate_target(target, values, actual_bits)
            if left != right:
                return {"status": "refuted", "inputs": values, "source": left, "target": right, "minimization": "lexicographically first small-domain actual-width counterexample"}
    return {"status": "no-small-counterexample", "width": 4, "cases": 16 ** len(inputs), "proof": False}

def model_values(text, count):
    values = {}
    for match in re.finditer(r"\(x(\d+)\s+(#x[0-9a-fA-F]+|#b[01]+|\(_\s+bv(\d+)\s+\d+\))\)", text):
        token = match[2]
        values[int(match[1])] = int(token[2:], 16 if token.startswith("#x") else 2) if token.startswith("#") else int(match[3])
    return [values[i] for i in range(count)] if set(values) == set(range(count)) else None

def minimize(source, target, values):
    inputs = validate(source)
    bits = source["nodes"][source["result"]]["bits"]
    values = list(values)
    def differs(v): return evaluate_source(source, v) != evaluate_target(target, v, bits)
    if any(v < 0 or v >= 1 << n["bits"] for v, n in zip(values, inputs)) or not differs(values):
        return None
    attempts = 0
    changed = True
    while changed and attempts < 4096:
        changed = False
        for i, node in enumerate(inputs):
            for bit in reversed(range(node["bits"])):
                if not values[i] & (1 << bit): continue
                trial = values.copy(); trial[i] &= ~(1 << bit)
                attempts += 1
                if differs(trial): values = trial; changed = True
                if attempts == 4096: break
            if attempts == 4096: break
    return {"inputs": values, "source": evaluate_source(source, values), "target": evaluate_target(target, values, bits), "minimization_attempts": attempts, "minimization_complete": not changed}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--extractor", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--solver", default="z3")
    parser.add_argument("--timeout-ms", type=int, default=1000)
    parser.add_argument("--max-candidates", type=int, default=16)
    args = parser.parse_args()
    if not 1 <= args.max_candidates <= 256 or not 1 <= args.timeout_ms <= 60000: parser.error("invalid resource bound")
    args.output_dir.mkdir(parents=True, exist_ok=False)
    digest = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
    report = {"format": "boundary-bitvector-search/v1", "image_sha256": digest(args.image), "extractor_sha256": digest(args.extractor), "required_solver_version": VERSION, "production_rewrite_authority": False, "limits": {"candidates": args.max_candidates, "solver_ms_per_query": args.timeout_ms, "minimization_attempts": 4096}, "candidates": []}
    try:
        extracted = subprocess.run([str(args.extractor), str(args.image)], capture_output=True, text=True, timeout=30)
    except (subprocess.TimeoutExpired, OSError) as error:
        report.update(status="not-proved", reason="extraction-unavailable-or-timeout", extraction_error=str(error))
        (args.output_dir / "report.json").write_text(json.dumps(report, indent=2)+"\n")
        return 2
    if extracted.returncode:
        report.update(status="not-proved", reason="unsupported-or-invalid-source", extraction_error=extracted.stderr)
    else:
        try:
            source = json.loads(extracted.stdout)
            validate(source)
            if source.get("image_sha256") != report["image_sha256"] or digest(args.image) != report["image_sha256"] or digest(args.extractor) != report["extractor_sha256"]:
                raise ValueError("extraction input or executable changed")
        except (ValueError, KeyError, TypeError, IndexError) as error:
            report.update(status="not-proved", reason="invalid-or-incomplete-extraction", extraction_error=str(error))
            (args.output_dir / "report.json").write_text(json.dumps(report, indent=2)+"\n")
            print(json.dumps({"status": report["status"], "candidates": 0, "output": str(args.output_dir)}))
            return 2
        (args.output_dir / "source.json").write_text(json.dumps(source, indent=2)+"\n")
        solver = shutil.which(args.solver)
        compatible = False
        if solver:
            try:
                report["solver_sha256"] = digest(solver)
                version = subprocess.run([solver, "-version"], capture_output=True, text=True, timeout=5)
                report["solver_version"] = version.stdout.strip()
                compatible = version.returncode == 0 and re.search(r"\bZ3 version 4\.15\.3\b", version.stdout) is not None and digest(solver) == report["solver_sha256"]
            except (subprocess.TimeoutExpired, OSError) as error:
                report["solver_error"] = str(error)
        for index, target in enumerate(candidates(source, args.max_candidates)):
            smt = query(source, target, args.timeout_ms)
            path = args.output_dir / f"candidate-{index:03}.smt2"
            path.write_text(smt)
            concrete = finite_counterexample(source, target)
            result = {"status": "not-proved", "reason": "missing-or-incompatible-solver"}
            start = time.perf_counter_ns()
            if compatible:
                try:
                    solved = subprocess.run([solver, "-in", "-smt2"], input=smt, capture_output=True, text=True, timeout=args.timeout_ms/1000+1)
                    result = classify(solved.stdout, solved.returncode)
                    result.update(stdout=solved.stdout, stderr=solved.stderr)
                    if result["status"] == "counterexample-exists":
                        count = len(validate(source))
                        if count == 0:
                            result["counterexample"] = minimize(source, target, [])
                            if result["counterexample"] is None: result.update(status="not-proved", reason="model-not-independently-validated")
                            report["candidates"].append({"target": target, "query": path.name, "query_sha256": hashlib.sha256(smt.encode()).hexdigest(), "solver": result, "elapsed_ns": time.perf_counter_ns()-start, "independent_check": concrete})
                            continue
                        model_query = smt + "(get-value (" + " ".join(f"x{i}" for i in range(count)) + "))\n"
                        model_path = args.output_dir / f"candidate-{index:03}-model.smt2"
                        model_path.write_text(model_query)
                        model = subprocess.run([solver, "-in", "-smt2"], input=model_query, capture_output=True, text=True, timeout=args.timeout_ms/1000+1)
                        values = model_values(model.stdout, count) if classify(model.stdout, model.returncode)["status"] == "counterexample-exists" else None
                        checked = minimize(source, target, values) if values is not None else None
                        result.update(model_query=model_path.name, model_stdout=model.stdout, counterexample=checked)
                        if checked is None: result.update(status="not-proved", reason="model-not-independently-validated")
                    if digest(solver) != report["solver_sha256"]: result = {"status": "not-proved", "reason": "solver-executable-changed"}
                except subprocess.TimeoutExpired: result = classify("", timed_out=True)
                except OSError as error: result = {"status": "not-proved", "reason": "solver-unavailable", "error": str(error)}
            if concrete["status"] == "refuted" and result["status"] == "equivalent":
                result = {"status": "not-proved", "reason": "independent-interpreter-disagrees"}
            report["candidates"].append({"target": target, "query": path.name, "query_sha256": hashlib.sha256(smt.encode()).hexdigest(), "solver": result, "elapsed_ns": time.perf_counter_ns()-start, "independent_check": concrete})
        report["status"] = "proved-candidates" if any(c["solver"]["status"] == "equivalent" for c in report["candidates"]) else "not-proved"
        if not compatible: report["reason"] = "missing-or-incompatible-solver"
    (args.output_dir / "report.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps({"status": report["status"], "candidates": len(report["candidates"]), "output": str(args.output_dir)}))
    return 0 if report["status"] == "proved-candidates" else 2

if __name__ == "__main__":
    raise SystemExit(main())
