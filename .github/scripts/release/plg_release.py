#!/usr/bin/env python3
"""Changelog + manifest helper for the plugin's releases (CHANGELOG.md <-> .plg CHANGES)."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import http.client
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

UNRELEASED = "Unreleased"
# Older releases used .HHMM suffixes; new ones are the date, then a, b, ... for a second release that day.
VERSION_RE = r"\d{4}\.\d{2}\.\d{2}(?:\.\d+|[a-z])?"
RELEASE_VERSION_RE = r"\d{4}\.\d{2}\.\d{2}[a-z]?"
TAG_GLOB = "[0-9][0-9][0-9][0-9].[0-9][0-9].[0-9][0-9]*"
# `rest` keeps any heading suffix verbatim (" - title", " and 2024.01.16.1", ...).
MD_HEADING_RE = re.compile(rf"^## (?P<ver>{VERSION_RE}|{UNRELEASED})(?P<beta> \(beta\))?(?P<rest>(?: .*)?)$")
PLG_HEADING_RE = re.compile(rf"^###(?P<ver>{VERSION_RE})(?P<rest>(?: .*)?)$")
ENTITY_RE = re.compile(r'<!ENTITY\s+(\w+)\s+"([^"]*)"\s*>')
PLUGIN_URL_BRANCH_RE = re.compile(r"^https://raw\.githubusercontent\.com/[^/]+/[^/]+/(?P<branch>[^/]+)/")
SEED_SKIP_RE = re.compile(
    r"^(Merge |Release |Auto-build|"
    r"(chore|ci|build|test|docs|style)(\([^)]*\))?!?: )|.*\[skip ci\]",
    re.IGNORECASE,
)


@dataclass
class Section:
    version: str
    beta: bool = False
    rest: str = ""
    body: list[str] = field(default_factory=list)
    # A heading that is not a version (a dashed date, "See previous releases..."): kept verbatim in `version`.
    note: bool = False

    @property
    def released(self) -> bool:
        return not self.note and self.version != UNRELEASED

    def bullets(self) -> list[str]:
        return [line for line in self.body if line.startswith("- ")]

    def sort_key(self) -> tuple:
        if not self.released:
            return (9999,)
        return tuple(int(p) if p.isdigit() else ord(p) for p in re.findall(r"\d+|[a-z]", self.version))


@dataclass
class Changelog:
    title: str = "Changelog"
    preamble: list[str] = field(default_factory=list)
    sections: list[Section] = field(default_factory=list)

    def find(self, version: str) -> Section | None:
        return next((s for s in self.sections if not s.note and s.version == version), None)

    def unreleased(self) -> Section | None:
        return self.find(UNRELEASED)

    def released(self, channel: str) -> list[Section]:
        return [s for s in self.sections if s.released and (channel == "beta" or not s.beta)]


class ChangelogError(Exception):
    pass


def _strip_blank_edges(lines: list[str]) -> list[str]:
    start, end = 0, len(lines)
    while start < end and not lines[start].strip():
        start += 1
    while end > start and not lines[end - 1].strip():
        end -= 1
    return lines[start:end]


def _check_body(version: str, body: list[str]) -> None:
    for line in body:
        if line.startswith("#"):
            raise ChangelogError(f"{version}: body line starts with '#', which would parse as a heading: {line!r}")


def parse_changelog(text: str) -> Changelog:
    lines = text.splitlines()
    if not lines or not lines[0].startswith("# "):
        raise ChangelogError("CHANGELOG must start with a '# Title' line")
    log = Changelog(title=lines[0][2:].strip())
    current: Section | None = None
    buf: list[str] = []
    seen: set[str] = set()

    def flush() -> None:
        body = _strip_blank_edges(buf)
        if current is None:
            log.preamble = body
        else:
            _check_body(current.version, body)
            current.body = body

    for line in lines[1:]:
        if not line.startswith("## "):
            buf.append(line)
            continue
        flush()
        m = MD_HEADING_RE.match(line)
        if m:
            ver = m.group("ver")
            # Historical plugin changelogs repeat a version heading now and then; only Unreleased must be unique.
            if ver == UNRELEASED and ver in seen:
                raise ChangelogError("duplicate Unreleased section")
            seen.add(ver)
            current = Section(ver, beta=bool(m.group("beta")), rest=m.group("rest"))
        else:
            current = Section(line[3:], note=True)
        log.sections.append(current)
        buf = []
    flush()
    return log


def format_changelog(log: Changelog) -> str:
    out = [f"# {log.title}", ""]
    if log.preamble:
        out += log.preamble + [""]
    for s in log.sections:
        heading = f"## {s.version}" if s.note else f"## {s.version}" + (" (beta)" if s.beta else "") + s.rest
        out += [heading, ""]
        if s.body:
            out += s.body + [""]
    return "\n".join(out).rstrip("\n") + "\n"


def load_changelog(path: Path) -> Changelog:
    return parse_changelog(path.read_text(encoding="utf-8"))


def save_changelog(path: Path, log: Changelog) -> None:
    path.write_text(format_changelog(log), encoding="utf-8")


def _xml_unescape(s: str) -> str:
    return s.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")


def _xml_escape(s: str) -> str:
    # XML only requires & and < in text; a bare > stays readable ("Array -> Cache") unless it closes "]]>".
    return s.replace("&", "&amp;").replace("<", "&lt;").replace("]]>", "]]&gt;")


def split_plg(text: str) -> tuple[list[str], list[str], list[str]]:
    """Return (lines before and incl. <CHANGES>, content lines, lines from </CHANGES> on)."""
    lines = text.splitlines()
    opens = [i for i, ln in enumerate(lines) if ln.strip() == "<CHANGES>"]
    closes = [i for i, ln in enumerate(lines) if ln.strip() == "</CHANGES>"]
    if len(opens) != 1 or len(closes) != 1 or closes[0] < opens[0]:
        raise ChangelogError("expected exactly one <CHANGES>...</CHANGES> block, each tag on its own line")
    return lines[: opens[0] + 1], lines[opens[0] + 1 : closes[0]], lines[closes[0] :]


def parse_changes(content: list[str]) -> Changelog:
    log = Changelog()
    current: Section | None = None
    buf: list[str] = []

    def flush() -> None:
        body = [_xml_unescape(ln) for ln in _strip_blank_edges(buf)]
        if current is None:
            log.preamble = body
        else:
            _check_body(current.version, body)
            current.body = body

    for line in content:
        if not line.startswith("###"):
            buf.append(line)
            continue
        flush()
        m = PLG_HEADING_RE.match(line)
        current = (Section(m.group("ver"), rest=_xml_unescape(m.group("rest"))) if m
                   else Section(_xml_unescape(line[3:]), note=True))
        log.sections.append(current)
        buf = []
    flush()
    return log


def render_changes(log: Changelog, channel: str) -> list[str]:
    out: list[str] = []
    if log.preamble:
        out += [_xml_escape(ln) for ln in log.preamble] + [""]
    blocks = []
    for s in log.sections:
        if s.note:
            blocks.append([f"###{_xml_escape(s.version)}"] + [_xml_escape(ln) for ln in s.body])
        elif s.released and (channel == "beta" or not s.beta):
            blocks.append([f"###{s.version}{_xml_escape(s.rest)}"] + [_xml_escape(ln) for ln in s.body])
    for i, block in enumerate(blocks):
        if i:
            out.append("")
        out += block
    return out + [""]


def write_changes(plg: Path, log: Changelog, channel: str) -> None:
    head, _, tail = split_plg(plg.read_text(encoding="utf-8"))
    plg.write_text("\n".join(head + render_changes(log, channel) + tail) + "\n", encoding="utf-8")


def changes_diff(plg: Path, log: Changelog, channel: str) -> str | None:
    _, current, _ = split_plg(plg.read_text(encoding="utf-8"))
    expected = render_changes(log, channel)
    if current == expected:
        return None
    for i, (a, b) in enumerate(zip(current, expected)):
        if a != b:
            return f"line {i + 1} of CHANGES differs:\n  plg:      {a!r}\n  expected: {b!r}"
    return f"CHANGES length differs: plg has {len(current)} lines, expected {len(expected)}"


def plg_entities(text: str) -> dict[str, str]:
    ents = dict(ENTITY_RE.findall(text))
    for _ in range(10):
        resolved = {k: re.sub(r"&(\w+);", lambda m: ents.get(m.group(1), m.group(0)), v) for k, v in ents.items()}
        if resolved == ents:
            break
        ents = resolved
    return ents


RELEASE_ENTITY_RE = re.compile(r'(<!ENTITY\s+(version|md5|pluginURL)\s+")([^"]*)("\s*>)')


def _without_release_fields(text: str) -> str:
    """The manifest with its per-branch parts blanked: release entities and the CHANGES block."""
    head, _, tail = split_plg(RELEASE_ENTITY_RE.sub(r"\1\4", text))
    return "\n".join(head + tail) + "\n"


def merge_manifest(base: str, ours: str, theirs: str) -> str:
    """Merge two branches' manifests, keeping ours' release entities; CHANGES is left empty for render."""
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for name, text in (("ours", ours), ("base", base), ("theirs", theirs)):
            path = Path(tmp) / name
            path.write_text(_without_release_fields(text), encoding="utf-8")
            paths.append(str(path))
        r = subprocess.run(["git", "merge-file", "-p", *paths], capture_output=True, text=True)
    if r.returncode != 0:
        raise ChangelogError("both branches changed the same part of the manifest outside its release fields; merge it by hand")
    keep = {m.group(2): m.group(3) for m in RELEASE_ENTITY_RE.finditer(ours)}
    if len(keep) != 3:
        raise ChangelogError("the manifest must declare version, md5 and pluginURL entities")
    return RELEASE_ENTITY_RE.sub(lambda m: m.group(1) + keep[m.group(2)] + m.group(4), r.stdout)


def package_url(text: str) -> str:
    m = re.search(r'<FILE\s+Name="[^"]*\.txz"[^>]*>\s*<URL>\s*([^<]+?)\s*</URL>', text)
    if not m:
        raise ChangelogError("no <FILE Name=\"...txz\"><URL> block found")
    ents = plg_entities(text)
    return re.sub(r"&(\w+);", lambda mm: ents.get(mm.group(1), mm.group(0)), m.group(1))


def fetch(url: str, attempts: int = 3) -> bytes:
    """Download a file; retries because release assets propagate and proxies truncate."""
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(url, timeout=60) as resp:
                return resp.read()
        except (OSError, http.client.HTTPException) as e:
            if attempt == attempts:
                raise OSError(str(e)) from e
            time.sleep(5 * attempt)
    raise OSError("unreachable")


def fetch_md5(url: str, attempts: int = 3) -> str:
    # usedforsecurity=False: the .plg format mandates md5; this is integrity, not security.
    return hashlib.md5(fetch(url, attempts), usedforsecurity=False).hexdigest()


def git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True, text=True).stdout


def commit_bullets(repo: Path, since: str, until: str, changelog: Path | None = None) -> list[str]:
    rng = f"{since}..{until}" if since else until
    paths = []
    if changelog is not None:
        rel = os.path.relpath(changelog.resolve(), repo.resolve())
        # an edit that only rewrites the notes (a web-UI "Update CHANGELOG.md") is not a change to announce
        paths = ["--", ".", f":(top,exclude){rel}"] if not rel.startswith("..") else []
    raw = git(repo, "log", "--no-merges", "--format=%h%x1f%s%x1f%an", rng, *paths)
    bullets = []
    for rec in raw.splitlines():
        sha, subject, author = rec.split("\x1f", 2)
        if author.endswith("[bot]") or SEED_SKIP_RE.match(subject):
            continue
        bullets.append(f"- {subject}" if re.match(r"^[a-z]+(\([^)]*\))?!?: ", subject) else f"- {subject} ({sha})")
    return bullets


def next_version(repo: Path, channel: str, date: str) -> str:
    taken = [t for t in git(repo, "tag", "-l", f"{date}*").split() if re.fullmatch(rf"{re.escape(date)}[a-z]?", t)]
    # A same-day beta never pushes the stable to a letter (strcmp then sorts <date> below <date>a: beta boxes need "forced")
    if channel == "stable" and date not in taken:
        return date
    letters = [t[-1] for t in taken if t != date]
    nxt = chr(ord(max(letters)) + 1) if letters else "a"
    if nxt > "z":
        raise ChangelogError(f"no version letter left for {date}")
    return date + nxt


def since_ref(repo: Path, log: Changelog, channel: str) -> str:
    """Tag of the channel's last release, or the nearest release tag, or "" for the whole history."""
    for s in log.released(channel):
        if git(repo, "tag", "-l", s.version).strip():
            return s.version
    try:
        return git(repo, "describe", "--tags", "--abbrev=0", "--match", TAG_GLOB).strip()
    except subprocess.CalledProcessError:
        return ""


def cmd_migrate(a) -> int:
    if a.changelog.exists() and not a.force:
        raise ChangelogError(f"{a.changelog} exists; pass --force to overwrite")
    _, content, _ = split_plg(a.plg.read_text(encoding="utf-8"))
    log = parse_changes(content)
    save_changelog(a.changelog, log)
    print(f"migrated {len(log.sections)} sections to {a.changelog}")
    return 0


def cmd_render(a) -> int:
    log = load_changelog(a.changelog)
    if a.check:
        diff = changes_diff(a.plg, log, a.channel)
        if diff:
            print(diff)
            return 1
        print("CHANGES matches CHANGELOG")
        return 0
    write_changes(a.plg, log, a.channel)
    print(f"rendered {len(log.released(a.channel))} sections into {a.plg}")
    return 0


def cmd_seed(a) -> int:
    log = load_changelog(a.changelog)
    if a.carry_from and a.carry_from.exists():
        old = load_changelog(a.carry_from).unreleased()
        if old:
            # release/<channel> outlives its cut: never carry a bullet this channel has released
            shipped = {b for s in log.released(a.channel) for b in s.bullets()}
            old.body = [line for line in old.body if line not in shipped]
            log.sections = [s for s in log.sections if s is not log.unreleased()]
            log.sections.insert(0, old)
    section = log.unreleased()
    if section is None:
        section = Section(UNRELEASED)
        log.sections.insert(0, section)
    new = []
    if a.beta_sections:
        # only betas newer than the ones this PR already took, so its edits and deletions stand
        after = Section(a.beta_after).sort_key() if a.beta_after else ()
        for s in log.released("beta"):
            if not s.beta:
                break
            if s.sort_key() > after:
                new = s.bullets() + new
    if a.since is not None:
        new += commit_bullets(a.repo, a.since, a.until, a.changelog)
    existing = set(section.bullets())
    added = [b for b in new if b not in existing and not (existing.add(b))]
    section.body += added
    save_changelog(a.changelog, log)
    print(f"seeded {len(added)} bullets; Unreleased now has {len(section.bullets())}")
    return 0


def cmd_stamp(a) -> int:
    log = load_changelog(a.changelog)
    section = log.unreleased()
    if section is None or (not section.bullets() and not a.allow_empty):
        raise ChangelogError("no Unreleased section with bullets to stamp")
    if not re.fullmatch(RELEASE_VERSION_RE, a.version):
        raise ChangelogError(f"version must look like YYYY.MM.DD or YYYY.MM.DDa (got {a.version!r})")
    if log.find(a.version):
        raise ChangelogError(f"section {a.version} already exists")
    section.version, section.beta = a.version, a.beta
    save_changelog(a.changelog, log)
    print(f"stamped Unreleased as {a.version}{' (beta)' if a.beta else ''}")
    return 0


def cmd_notes(a) -> int:
    section = load_changelog(a.changelog).find(a.version)
    if section is None:
        raise ChangelogError(f"no section {a.version}")
    print("\n".join(section.body))
    if a.footer:
        print("\n" + a.footer)
    return 0


def manifest_problems(ents: dict[str, str], log: Changelog, channel: str, branch: str) -> list[str]:
    problems = []
    m = PLUGIN_URL_BRANCH_RE.match(ents.get("pluginURL", ""))
    if not m:
        problems.append(f"pluginURL entity is not a raw.githubusercontent URL: {ents.get('pluginURL')!r}")
    elif m.group("branch") != branch:
        problems.append(f"pluginURL points at branch {m.group('branch')!r}, expected {branch!r}")
    if not re.fullmatch(r"[0-9a-f]{32}", ents.get("md5", "")):
        problems.append("md5 entity is not a 32-char hex digest")
    if not any(s.version == ents.get("version") for s in log.released(channel)):
        problems.append(f"version entity {ents.get('version')!r} has no matching CHANGELOG section for channel {channel}")
    return problems


def unreleased_problems(log: Changelog, a) -> list[str]:
    section = log.unreleased()
    if section is None or not section.bullets():
        return ["Unreleased section is missing or has no bullets"] if a.require_nonempty else []
    if not a.require_edited:
        return []
    # a bullet still word for word what `seed` wrote from a commit subject has not been edited
    since = a.since if a.since is not None else since_ref(a.repo, log, a.channel)
    seeded = set(commit_bullets(a.repo, since, "HEAD", a.changelog))
    raw = [b for b in section.bullets() if b in seeded]
    return ["Unreleased still has bullets copied from commit subjects:\n  " + "\n  ".join(raw)] if raw else []


def asset_problems(text: str, md5: str | None) -> list[str]:
    url = package_url(text)
    try:
        digest = fetch_md5(url)
    except OSError as e:
        return [f"could not download {url}: {e}"]
    if digest != md5:
        return [f"asset at {url} has md5 {digest}, plg says {md5}"]
    print(f"asset md5 verified: {url}")
    return []


def cmd_check(a) -> int:
    log = load_changelog(a.changelog)
    text = a.plg.read_text(encoding="utf-8")
    ents = plg_entities(text)
    diff = changes_diff(a.plg, log, a.channel)
    problems = ([diff] if diff else []) + manifest_problems(ents, log, a.channel, a.branch) + unreleased_problems(log, a)
    if a.verify_asset and not problems:
        problems = asset_problems(text, ents.get("md5"))
    for p in problems:
        print(f"ERROR: {p}")
    if not problems:
        print("check passed")
    return 1 if problems else 0


def cmd_verify_manifest(a) -> int:
    """Check a released manifest still installs: its package downloads and matches its md5."""
    text = fetch(a.url).decode("utf-8")
    ents = plg_entities(text)
    url = package_url(text)
    digest = fetch_md5(url)
    if digest != ents.get("md5"):
        print(f"ERROR: {url} has md5 {digest}, the manifest at {a.url} says {ents.get('md5')}", file=sys.stderr)
        return 1
    print(f"upgrade={ents.get('upgrade', '')}")
    return 0


def cmd_next_version(a) -> int:
    date = a.date or dt.datetime.now(ZoneInfo(a.tz)).strftime("%Y.%m.%d")
    print(next_version(a.repo, a.channel, date))
    return 0


def cmd_since_ref(a) -> int:
    print(since_ref(a.repo, load_changelog(a.changelog), a.channel))
    return 0


def cmd_merge_manifest(a) -> int:
    base, ours, theirs = (p.read_text(encoding="utf-8") for p in (a.base, a.ours, a.theirs))
    a.out.write_text(merge_manifest(base, ours, theirs), encoding="utf-8")
    print(f"merged the manifest into {a.out}")
    return 0


def cmd_last_beta(a) -> int:
    """Print the newest beta release in the changelog, or nothing."""
    newest = max((s for s in load_changelog(a.changelog).released("beta") if s.beta), key=Section.sort_key, default=None)
    if newest:
        print(newest.version)
    return 0


def cmd_merge_changelog(a) -> int:
    """Insert theirs-only released sections into ours by version; ours keeps its order."""
    ours, theirs = load_changelog(a.ours), load_changelog(a.theirs)
    have = {s.version for s in ours.sections if s.released}
    missing = [s for s in theirs.sections if s.released and s.version not in have]
    for s in reversed(missing):
        idx = next((i for i, o in enumerate(ours.sections) if o.released and o.sort_key() < s.sort_key()),
                   len(ours.sections))
        ours.sections.insert(idx, s)
    save_changelog(a.out, ours)
    print(f"merged changelog has {len(ours.sections)} sections ({len(missing)} added)")
    return 0


def cmd_last_version(a) -> int:
    released = load_changelog(a.changelog).released(a.channel)
    if not released:
        raise ChangelogError(f"no released sections for channel {a.channel}")
    print(released[0].version)
    return 0


def cmd_entity(a) -> int:
    ents = plg_entities(a.plg.read_text(encoding="utf-8"))
    if a.name not in ents:
        raise ChangelogError(f"no entity {a.name}")
    print(ents[a.name])
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    def add(name, fn, **flags):
        sp = sub.add_parser(name)
        sp.set_defaults(fn=fn)
        for flag, kw in flags.items():
            sp.add_argument(flag, **kw)
        return sp

    repo = {"--repo": dict(type=Path, default=Path("."))}
    add("migrate", cmd_migrate, **{"--plg": dict(type=Path, required=True), "--changelog": dict(type=Path, required=True),
        "--force": dict(action="store_true")})
    add("render", cmd_render, **{"--plg": dict(type=Path, required=True), "--changelog": dict(type=Path, required=True),
        "--channel": dict(choices=["stable", "beta"], required=True), "--check": dict(action="store_true")})
    add("seed", cmd_seed, **{"--changelog": dict(type=Path, required=True), "--carry-from": dict(type=Path),
        "--channel": dict(choices=["stable", "beta"], required=True), "--since": dict(default=None),
        "--until": dict(default="HEAD"), "--beta-sections": dict(action="store_true"), "--beta-after": dict(default=""),
        **repo})
    add("stamp", cmd_stamp, **{"--changelog": dict(type=Path, required=True), "--version": dict(required=True),
        "--beta": dict(action="store_true"), "--allow-empty": dict(action="store_true")})
    add("notes", cmd_notes, **{"--changelog": dict(type=Path, required=True), "--version": dict(required=True),
        "--footer": dict(default="")})
    add("check", cmd_check, **{"--changelog": dict(type=Path, required=True), "--plg": dict(type=Path, required=True),
        "--channel": dict(choices=["stable", "beta"], required=True), "--branch": dict(required=True),
        "--require-edited": dict(action="store_true"), "--require-nonempty": dict(action="store_true"),
        "--verify-asset": dict(action="store_true"), "--since": dict(default=None), **repo})
    add("verify-manifest", cmd_verify_manifest, **{"--url": dict(required=True)})
    add("next-version", cmd_next_version, **{"--channel": dict(choices=["stable", "beta"], required=True),
        "--tz": dict(default="UTC"), "--date": dict(default=""), **repo})
    add("since-ref", cmd_since_ref, **{"--changelog": dict(type=Path, required=True),
        "--channel": dict(choices=["stable", "beta"], required=True), **repo})
    add("merge-manifest", cmd_merge_manifest, **{"--base": dict(type=Path, required=True),
        "--ours": dict(type=Path, required=True), "--theirs": dict(type=Path, required=True),
        "--out": dict(type=Path, required=True)})
    add("last-beta", cmd_last_beta, **{"--changelog": dict(type=Path, required=True)})
    add("merge-changelog", cmd_merge_changelog, **{"--ours": dict(type=Path, required=True),
        "--theirs": dict(type=Path, required=True), "--out": dict(type=Path, required=True)})
    add("last-version", cmd_last_version, **{"--changelog": dict(type=Path, required=True),
        "--channel": dict(choices=["stable", "beta"], required=True)})
    add("entity", cmd_entity, **{"--plg": dict(type=Path, required=True), "--name": dict(required=True)})
    return p


def main(argv: list[str] | None = None) -> int:
    """Exit 0 = ok, 1 = the check found problems, 2 = this command could not run."""
    a = build_parser().parse_args(argv)
    try:
        return a.fn(a)
    except subprocess.CalledProcessError as e:
        print(f"ERROR: {e}\n{(e.stderr or '').strip()}", file=sys.stderr)
        return 2
    except (ChangelogError, OSError, UnicodeDecodeError, ZoneInfoNotFoundError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
