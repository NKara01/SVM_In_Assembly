#!/usr/bin/env python3
import os
import re
import subprocess
import tempfile

import numpy as np
from sklearn.datasets import make_blobs, make_moons
from sklearn.svm import SVC

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JAR = os.path.join(ROOT, "tools", "Mars.jar")
ASM = os.path.join(ROOT, "asm", "svm.asm")


def run_mips(coords, path, C, gamma, tol, max_sweeps):
    lines = ["1", path, "2", f"{C} {gamma} {tol} {max_sweeps}", "3"]
    for row in coords:
        lines.append("4")
        lines.append(" ".join(repr(float(v)) for v in row))
    lines.extend(["5", "6", "7", ""])
    proc = subprocess.run(
        ["java", "-jar", JAR, "nc", "ae1", ASM],
        input="\n".join(lines),
        text=True,
        capture_output=True,
        timeout=120,
    )
    out = proc.stdout
    decisions = [float(x) for x in re.findall(r"DECISION\s+([^\s]+)", out)]
    classes = [int(x) for x in re.findall(r"CLASS\s+(-?\d+)", out)]
    acc = re.search(r"ACCURACY\s+([^\s]+)", out)
    nsv = re.search(r"N_SV\s+(\d+)", out)
    bias = re.search(r"BIAS\s+([^\s]+)", out)
    if proc.returncode != 0:
        raise AssertionError(f"MARS exit {proc.returncode}\n{out}\n{proc.stderr}")
    if "ERROR" in out:
        raise AssertionError(f"MIPS error:\n{out}")
    return {
        "decisions": np.array(decisions),
        "classes": np.array(classes),
        "accuracy": float(acc.group(1)) if acc else None,
        "nsv": int(nsv.group(1)) if nsv else None,
        "bias": float(bias.group(1)) if bias else None,
        "out": out,
    }


def check(name, X, y, C=1.0, gamma=0.5, tol=1e-4, max_sweeps=2000):
    y = np.where(y > 0, 1, -1).astype(int)
    clf = SVC(kernel="rbf", C=C, gamma=gamma, tol=tol, max_iter=1000000)
    clf.fit(X, y)
    ref_dec = clf.decision_function(X)
    ref_acc = float(np.mean(clf.predict(X) == y))

    fd, path = tempfile.mkstemp(suffix=".txt", prefix="svmdata_")
    os.close(fd)
    try:
        with open(path, "w") as f:
            f.write(f"{len(X)} {X.shape[1]}\n")
            for row, label in zip(X, y):
                vals = " ".join(repr(float(v)) for v in row)
                f.write(f"{label} {vals}\n")
        got = run_mips(X, path, C, gamma, tol, max_sweeps)
    finally:
        os.unlink(path)

    got_dec = got["decisions"]
    assert len(got_dec) == len(X), (len(got_dec), len(X), got["out"])
    max_diff = float(np.max(np.abs(got_dec - ref_dec)))
    sign_agree = float(np.mean(np.sign(got_dec) == np.sign(ref_dec)))
    got_acc = got["accuracy"]
    print(
        f"{name}: n={len(X)} d={X.shape[1]} sweeps/nsv={got['nsv']} "
        f"max|dec diff|={max_diff:.3e} sign_agree={sign_agree:.3f} "
        f"acc={got_acc:.4f} ref_acc={ref_acc:.4f} bias={got['bias']:.6g}"
    )
    assert sign_agree == 1.0, got["out"]
    assert max_diff < 5e-3, (max_diff, got["out"])
    assert got_acc is not None and abs(got_acc - ref_acc) < 1e-9


def main():
    rng = np.random.default_rng(7)

    X = np.array(
        [[-1.0, -1.0], [-1.0, 1.0], [1.0, 1.0], [1.0, -1.0]]
    )
    y = np.array([-1, 1, -1, 1])
    check("xor", X, y, gamma=0.5)

    X, y = make_blobs(
        n_samples=30, n_features=2, centers=3, cluster_std=0.8, random_state=3
    )
    y = np.where(y % 2 == 0, 1, -1)
    check("blobs", X, y, C=1.0, gamma=0.5)

    X, y = make_moons(n_samples=40, noise=0.12, random_state=4)
    y = np.where(y == 0, -1, 1)
    check("moons", X, y, C=1.0, gamma=1.0)

    X = rng.normal(size=(35, 3))
    y = np.where(X[:, 0] + 0.5 * X[:, 1] * X[:, 2] > 0, 1, -1)
    check("random3d", X, y, C=2.0, gamma=0.7)

    X, y = make_blobs(
        n_samples=50, n_features=4, centers=2, cluster_std=1.1, random_state=9
    )
    check("blobs4d", X, y, C=0.8, gamma=0.3)

    X = np.array([[-1.0, -1.0], [-1.0, 1.0], [1.0, 1.0], [1.0, -1.0]]) * 1e-5
    y = np.array([-1, 1, -1, 1])
    check("tiny-exponent", X, y, gamma=1e10)


if __name__ == "__main__":
    main()
