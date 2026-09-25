import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
REPO = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(SCRIPTS))
import plg_release as pr  # noqa: E402

PLG = """<?xml version='1.0' standalone='yes'?>
<!DOCTYPE PLUGIN [
<!ENTITY name      "ca.mover.tuning">
<!ENTITY author    "someone">
<!ENTITY version   "2026.08.28">
<!ENTITY md5       "0123456789abcdef0123456789abcdef">
<!ENTITY github    "someone/&name;">
<!ENTITY upgrade   "minor">
<!ENTITY pluginURL "https://raw.githubusercontent.com/&github;/beta/plugins/&name;.plg">
]>

<PLUGIN name="&name;" version="&version;" pluginURL="&pluginURL;">

<CHANGES>
###2026.08.28
- fix: Array -> Cache moves stop at the fill-up limit &amp; log it &lt;once>
- new: Settings keep their values

###2026.08.14 - Titled release
- Uninstalling now removes the plugin cleanly

###2025.04.24a
- Same-day letter release

###2025.02.18.1752
- Release with a time suffix
2025.02.18.0115
- a folded note line

###2024-06-30
- Dashed heading from the early days

###2024.05.01
- Duplicate heading one

###2024.05.01
- Duplicate heading two

### See previous releases for earlier notes...

</CHANGES>

<FILE Name="/boot/config/plugins/&name;/&name;-&version;-x86_64-1.txz" Run="upgradepkg --install-new">
<URL>https://github.com/&github;/releases/download/&version;/&name;-&version;-x86_64-1.txz</URL>
<MD5>&md5;</MD5>
</FILE>
</PLUGIN>
"""

OLD_PLG = """<?xml version='1.0' standalone='yes'?>
<!DOCTYPE PLUGIN [
<!ENTITY name      "ca.mover.tuning">
<!ENTITY version   "2026.08.01">
<!ENTITY md5       "fedcba9876543210fedcba9876543210">
<!ENTITY github    "someone/&name;">
<!ENTITY branch    "master">
<!ENTITY upgrade   "major">
]>
<PLUGIN name="&name;" version="&version;">
<FILE Name="/boot/config/plugins/&name;/&name;-&version;-x86_64-1.txz" Run="upgradepkg --install-new">
<URL>https://github.com/&github;/raw/&branch;/archive/&name;-&version;-x86_64-1.txz</URL>
<MD5>&md5;</MD5>
</FILE>
</PLUGIN>
"""


def run(*argv):
    return pr.main([str(a) for a in argv])


@pytest.fixture
def plg(tmp_path):
    p = tmp_path / "ca.mover.tuning.plg"
    p.write_text(PLG)
    return p, tmp_path / "CHANGELOG.md"


def test_migrate_then_render_is_byte_identical(plg):
    p, changelog = plg
    assert run("migrate", "--plg", p, "--changelog", changelog) == 0
    assert run("render", "--plg", p, "--changelog", changelog, "--channel", "beta") == 0
    assert p.read_text() == PLG
    assert run("render", "--plg", p, "--changelog", changelog, "--channel", "beta", "--check") == 0


def test_migrate_unescapes_and_keeps_heading_suffixes(plg):
    p, changelog = plg
    run("migrate", "--plg", p, "--changelog", changelog)
    text = changelog.read_text()
    assert "- fix: Array -> Cache moves stop at the fill-up limit & log it <once>\n" in text
    assert "## 2026.08.14 - Titled release\n" in text
    assert pr.load_changelog(changelog).find("2026.08.14").rest == " - Titled release"


def test_escaping_covers_what_xml_requires_and_leaves_arrows_readable():
    """&copy; is undeclared and would break the manifest; a bare > is valid text unless it closes ]]>."""
    assert pr._xml_escape("Tom & Jerry, &copy; 2026, <b>") == "Tom &amp; Jerry, &amp;copy; 2026, &lt;b>"
    assert pr._xml_escape("Array -> Cache") == "Array -> Cache"
    assert pr._xml_escape("x ]]> y") == "x ]]&gt; y"


def test_old_version_shapes_are_releases_and_other_headings_are_kept_verbatim(plg):
    p, changelog = plg
    run("migrate", "--plg", p, "--changelog", changelog)
    log = pr.load_changelog(changelog)
    assert [s.version for s in log.released("stable")] == [
        "2026.08.28", "2026.08.14", "2025.04.24a", "2025.02.18.1752", "2024.05.01", "2024.05.01"]
    assert [s.version for s in log.sections if s.note] == ["2024-06-30", " See previous releases for earlier notes..."]
    assert "\n##  See previous releases for earlier notes...\n" in changelog.read_text()
    assert log.find("2024-06-30") is None, "a heading that is not a version is never a release"


def test_stable_channel_hides_beta_sections(plg):
    p, changelog = plg
    run("migrate", "--plg", p, "--changelog", changelog)
    changelog.write_text(changelog.read_text().replace("## 2025.04.24a\n", "## 2025.04.24a (beta)\n"))
    run("render", "--plg", p, "--changelog", changelog, "--channel", "stable")
    assert "###2025.04.24a" not in p.read_text()
    assert "###2024-06-30\n" in p.read_text(), "headings that are not versions show on both channels"
    run("render", "--plg", p, "--changelog", changelog, "--channel", "beta")
    assert "###2025.04.24a\n- Same-day letter release" in p.read_text()


def test_body_line_that_looks_like_heading_is_rejected(plg):
    p, changelog = plg
    run("migrate", "--plg", p, "--changelog", changelog)
    changelog.write_text(changelog.read_text().replace("- Same-day letter release", "- Same-day letter release\n#### oops"))
    with pytest.raises(pr.ChangelogError):
        pr.load_changelog(changelog)


def test_duplicate_released_heading_tolerated_but_unreleased_unique(plg):
    p, changelog = plg
    run("migrate", "--plg", p, "--changelog", changelog)
    assert [s.version for s in pr.load_changelog(changelog).sections].count("2024.05.01") == 2
    changelog.write_text(changelog.read_text() + "\n## Unreleased\n\n- a\n\n## Unreleased\n\n- b\n")
    with pytest.raises(pr.ChangelogError):
        pr.load_changelog(changelog)


def test_stamp_notes_and_check_flags(plg):
    p, changelog = plg
    run("migrate", "--plg", p, "--changelog", changelog)
    text = changelog.read_text().replace("\n## 2026.08.28\n", "\n## Unreleased\n\n- Settings page loads faster (#9)\n\n## 2026.08.28\n", 1)
    changelog.write_text(text)
    assert run("check", "--changelog", changelog, "--plg", p, "--channel", "beta", "--branch", "beta") == 0
    assert run("check", "--changelog", changelog, "--plg", p, "--channel", "beta", "--branch", "master") == 1
    assert run("stamp", "--changelog", changelog, "--version", "2026.09.05a", "--beta") == 0
    assert "## 2026.09.05a (beta)\n\n- Settings page loads faster (#9)" in changelog.read_text()
    assert run("stamp", "--changelog", changelog, "--version", "2026.09.05b", "--beta") == 2
    assert run("check", "--changelog", changelog, "--plg", p, "--channel", "beta", "--branch", "beta", "--require-nonempty") == 1
    run("render", "--plg", p, "--changelog", changelog, "--channel", "beta")
    assert "<CHANGES>\n###2026.09.05a\n- Settings page loads faster (#9)\n\n###2026.08.28" in p.read_text()
    assert run("notes", "--changelog", changelog, "--version", "2026.09.05a", "--footer", "Install: x") == 0


def test_stamp_rejects_a_version_a_release_cannot_have(tmp_path):
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text("# Changelog\n\n## Unreleased\n\n- something\n")
    for bad in ("1", "v2026.09.05", "2026.9.5", "latest", "2026.09.05.1", "2026.09.05ab", "2026.09.05A"):
        assert run("stamp", "--changelog", changelog, "--version", bad) == 2, bad
    assert "## Unreleased" in changelog.read_text(), "a rejected stamp must not mutate the file"
    assert run("stamp", "--changelog", changelog, "--version", "2026.09.05a") == 0


def test_release_token_is_absent_from_git_config_during_the_build(tmp_path):
    """The build command must not be able to read the token out of .git/config."""
    subprocess.run(["git", "init", "-q", "-b", "master", str(tmp_path)], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "remote", "add", "origin",
                    "https://github.com/someone/plugin.git"], check=True)
    probe = tmp_path / "seen.txt"
    script = """
set -euo pipefail
cd "$1"
. "$2/plg_release_git.sh"
plg_git_setup
grep -c 'SEKRIT' .git/config >> "$3" || true   # before: token attached
plg_git_deauth
grep -c 'SEKRIT' .git/config >> "$3" || true   # during the build: must be 0
plg_git_auth
grep -c 'SEKRIT' .git/config >> "$3" || true   # after: reattached for the push
"""
    env = {**os.environ, "GH_TOKEN": "SEKRIT", "GITHUB_REPOSITORY": "someone/plugin",
           "GIT_USER": "someone", "GIT_EMAIL": "s@example.com"}
    subprocess.run(["bash", "-c", script, "sh", str(tmp_path), str(SCRIPTS), str(probe)],
                   check=True, env=env, capture_output=True)
    before, during, after = probe.read_text().split()
    assert (before, during, after) == ("1", "0", "1"), probe.read_text()


def _step(step_id):
    import yaml

    wf = yaml.safe_load((REPO / ".github/workflows/release.yml").read_text())
    return next(s for s in wf["jobs"]["release"]["steps"] if s.get("id") == step_id)["run"]


def _git(repo, *args):
    return subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True, text=True).stdout.strip()


@pytest.fixture
def decide_repo(tmp_path):
    """master: base commit, a merged release PR's merge commit, then one more push."""
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init", "-q", "-b", "master")
    _git(repo, "config", "user.email", "t@example.com")
    _git(repo, "config", "user.name", "t")
    shas = []
    for msg in ("base", "Merge pull request #7 from someone/release/stable", "later push"):
        (repo / "f").write_text(msg)
        _git(repo, "add", "f")
        _git(repo, "commit", "-qm", msg)
        shas.append(_git(repo, "rev-parse", "HEAD"))
    return repo, shas[1]


def _run_decide(tmp_path, repo, mode, gh_body, ref_name="master"):
    """Run the workflow's 'Decide channel and mode' step against a stub gh."""
    bindir = tmp_path / "bin"
    bindir.mkdir(exist_ok=True)
    (bindir / "gh").write_text("#!/bin/bash\n" + gh_body + "\n")
    (bindir / "gh").chmod(0o755)
    out = tmp_path / "out.txt"
    out.write_text("")
    env = {**os.environ, "PATH": f"{bindir}:{os.environ['PATH']}", "MODE_IN": mode, "GITHUB_REF_NAME": ref_name,
           "STABLE_BRANCH": "master", "BETA_BRANCH": "beta", "GITHUB_OUTPUT": str(out),
           "GITHUB_REPOSITORY": "someone/plugin"}
    r = subprocess.run(["bash", "-c", _step("decide")], cwd=repo, env=env, capture_output=True, text=True)
    return r, dict(line.split("=", 1) for line in out.read_text().splitlines())


@pytest.mark.parametrize("mode", ["relase", "", "RELEASE", "release; rm -rf /"])
def test_decide_rejects_an_unsupported_mode(tmp_path, decide_repo, mode):
    r, _ = _run_decide(tmp_path, decide_repo[0], mode, "exit 0")
    assert r.returncode == 1, r.stdout
    assert "mode must be auto, pr or release" in r.stdout + r.stderr


@pytest.mark.parametrize("mode", ["pr", "release"])
def test_decide_takes_an_explicit_mode_as_given(tmp_path, decide_repo, mode):
    r, out = _run_decide(tmp_path, decide_repo[0], mode, "exit 1")
    assert r.returncode == 0, r.stderr
    assert out["mode"] == mode


def test_decide_releases_a_merged_release_pr_until_a_release_tag_contains_it(tmp_path, decide_repo):
    """A cancelled run must not lose the release: the next run sees the merge still has no release tag."""
    repo, merged = decide_repo
    gh = f"echo '7 {merged}'"
    r, out = _run_decide(tmp_path, repo, "auto", gh)
    assert r.returncode == 0, r.stderr
    assert (out["channel"], out["mode"], out["pr_number"]) == ("stable", "release", "7")
    _git(repo, "tag", "pr-12-2026.09.19.0260925010101", "HEAD")
    assert _run_decide(tmp_path, repo, "auto", gh)[1]["mode"] == "release", "a PR test build's tag is not a release"
    _git(repo, "tag", "2026.09.26", "HEAD")
    assert _run_decide(tmp_path, repo, "auto", gh)[1]["mode"] == "pr"


def test_decide_refreshes_the_pr_when_no_release_pr_is_due(tmp_path, decide_repo):
    repo, _ = decide_repo
    assert _run_decide(tmp_path, repo, "auto", "echo ' '")[1]["mode"] == "pr"
    assert _run_decide(tmp_path, repo, "auto", "echo '7 " + "f" * 40 + "'")[1]["mode"] == "pr"


def test_decide_stops_when_the_pr_lookup_fails(tmp_path, decide_repo):
    """Guessing "refresh" on an API error would silently skip a due release."""
    r, out = _run_decide(tmp_path, decide_repo[0], "auto", "echo 'HTTP 502' >&2; exit 1")
    assert r.returncode != 0 and "mode" not in out


def test_decide_skips_a_branch_that_is_not_a_channel(tmp_path, decide_repo):
    assert _run_decide(tmp_path, decide_repo[0], "auto", "exit 1", ref_name="feature")[1]["mode"] == "skip"


def test_backmerge_tolerates_an_already_merged_base():
    """A dry-run cut leaves the base already merged, so the back-merge stages nothing."""
    body = (SCRIPTS / "plg_release_backmerge.sh").read_text()
    assert "git commit -q --allow-empty" in body


def test_cut_names_the_recovery_command_when_publishing_fails():
    """No auto-rollback: a failure between tagging and the base push must say how to undo it."""
    body = (SCRIPTS / "plg_release_cut.sh").read_text()
    trap, tag, push, disarm = (body.index(t) for t in
                               ("trap 'echo", 'git tag "$version"', 'git push -q origin "HEAD:$BASE"', "trap - ERR"))
    assert trap < tag < push < disarm, "the guidance must be armed before tagging and cleared after the push"
    assert "gh release delete $version --cleanup-tag" in body
    assert "git push --delete origin refs/tags/$version" in body, "the tag-only failure needs its own remedy"
    assert "gh release delete" not in body.split("trap - ERR")[1], "nothing may delete a release automatically"


@pytest.fixture
def repo(tmp_path):
    def sh(*args):
        subprocess.run(["git", *args], cwd=tmp_path, check=True, capture_output=True)

    sh("init", "-q", "-b", "master")
    sh("config", "user.email", "t@example.com")
    sh("config", "user.name", "t")
    (tmp_path / "f").write_text("0")
    sh("add", "f")
    sh("commit", "-qm", "chore: initial")
    sh("tag", "2026.09.04")
    for msg in ["fix(ui): keep share order (#63)", "chore(deps): update actions", "Merge branch x",
                "feat: new thing", "ci: tweak workflow", "Auto-build: ca.mover.tuning-2026.09.05-x86_64-1.txz",
                "docs: readme", "Plain subject"]:
        (tmp_path / "f").write_text(msg)
        sh("commit", "-qam", msg)
    return tmp_path


def test_require_edited_flags_bullets_still_copied_from_commits(repo):
    """Edited means changed from what seed wrote; the maintainer's own `- fix:` style is not a raw subject."""
    p = repo / "p.plg"
    p.write_text(PLG)
    changelog = repo / "CHANGELOG.md"
    run("migrate", "--plg", p, "--changelog", changelog)
    sha = subprocess.run(["git", "log", "-1", "--format=%h"], cwd=repo, check=True, capture_output=True,
                         text=True).stdout.strip()
    args = ("check", "--changelog", changelog, "--plg", p, "--channel", "beta", "--branch", "beta",
            "--require-edited", "--since", "2026.09.04", "--repo", repo)

    def with_unreleased(bullet):
        base = pr.load_changelog(changelog)
        base.sections = [s for s in base.sections if s is not base.unreleased()]
        base.sections.insert(0, pr.Section(pr.UNRELEASED, body=[bullet]))
        pr.save_changelog(changelog, base)

    with_unreleased(f"- Plain subject ({sha})")  # seed shape: subject + short sha
    assert run(*args) == 1
    with_unreleased("- feat: new thing")  # seed shape: a conventional subject, word for word
    assert run(*args) == 1
    with_unreleased("- Plain subject")  # edited: the hash is gone
    assert run(*args) == 0
    with_unreleased("- fix: Transfer completion is verified before success is reported")
    assert run(*args) == 0


def test_git_failure_surfaces_stderr(tmp_path, capsys):
    changelog = tmp_path / "c.md"
    changelog.write_text("# Changelog\n\n## 2026.09.05\n\n- x\n")
    assert run("seed", "--changelog", changelog, "--since", "does-not-exist", "--repo", tmp_path) == 2
    err = capsys.readouterr().err
    assert "not a git repository" in err.lower() or "unknown revision" in err.lower()


def test_execution_errors_exit_2_not_1(tmp_path):
    missing = tmp_path / "nope.md"
    p = tmp_path / "nope.plg"
    assert run("check", "--changelog", missing, "--plg", p, "--channel", "stable", "--branch", "master") == 2
    assert run("next-version", "--channel", "stable", "--tz", "Mars/Olympus", "--repo", tmp_path) == 2


def test_check_reports_unsynced_plg(plg):
    p, changelog = plg
    run("migrate", "--plg", p, "--changelog", changelog)
    p.write_text(p.read_text().replace("- new: Settings keep their values\n", ""))
    assert run("check", "--changelog", changelog, "--plg", p, "--channel", "beta", "--branch", "beta") == 1


def test_verify_asset_compares_md5_and_reports_download_failure(plg, monkeypatch):
    p, changelog = plg
    run("migrate", "--plg", p, "--changelog", changelog)
    args = ("check", "--changelog", changelog, "--plg", p, "--channel", "beta", "--branch", "beta", "--verify-asset")
    monkeypatch.setattr(pr, "fetch_md5", lambda url, attempts=3: "0123456789abcdef0123456789abcdef")
    assert run(*args) == 0
    monkeypatch.setattr(pr, "fetch_md5", lambda url, attempts=3: "0" * 32)
    assert run(*args) == 1
    monkeypatch.setattr(pr, "fetch_md5", lambda url, attempts=3: (_ for _ in ()).throw(OSError("truncated")))
    assert run(*args) == 1


def test_fetch_retries_then_raises(monkeypatch):
    calls = []

    def boom(url, timeout):
        calls.append(url)
        raise pr.http.client.IncompleteRead(b"x")

    monkeypatch.setattr(pr.urllib.request, "urlopen", boom)
    monkeypatch.setattr(pr.time, "sleep", lambda s: None)
    with pytest.raises(OSError):
        pr.fetch("https://example.invalid/x.txz", attempts=3)
    assert len(calls) == 3


def test_package_url_resolves_nested_entities_in_both_manifest_shapes():
    assert pr.package_url(PLG) == (
        "https://github.com/someone/ca.mover.tuning/releases/download/2026.08.28/ca.mover.tuning-2026.08.28-x86_64-1.txz")
    assert pr.package_url(OLD_PLG) == (
        "https://github.com/someone/ca.mover.tuning/raw/master/archive/ca.mover.tuning-2026.08.01-x86_64-1.txz")


def test_verify_manifest_checks_the_released_package(monkeypatch, capsys):
    package = b"package bytes"
    manifest = OLD_PLG.replace("fedcba9876543210fedcba9876543210", hashlib.md5(package).hexdigest())
    served = {"https://example.invalid/m.plg": manifest.encode(), pr.package_url(OLD_PLG): package}
    monkeypatch.setattr(pr, "fetch", lambda url, attempts=3: served[url])
    assert run("verify-manifest", "--url", "https://example.invalid/m.plg") == 0
    assert capsys.readouterr().out.strip() == "upgrade=major"
    served[pr.package_url(OLD_PLG)] = b"something else"
    assert run("verify-manifest", "--url", "https://example.invalid/m.plg") == 1

    def gone(url, attempts=3):
        raise OSError("HTTP Error 404")

    monkeypatch.setattr(pr, "fetch", gone)
    assert run("verify-manifest", "--url", "https://example.invalid/m.plg") == 2


def test_commit_bullets_filters_noise(repo):
    bullets = pr.commit_bullets(repo, "2026.09.04", "HEAD")
    assert [b.split(" (")[0] for b in bullets] == ["- Plain subject", "- feat: new thing", "- fix(ui): keep share order"]


def test_seed_is_append_only_and_carries_edits(repo):
    changelog = repo / "CHANGELOG.md"
    changelog.write_text("# Changelog\n\n## 2026.09.04\n\n- Old\n")
    old = repo / "old.md"
    old.write_text("# Changelog\n\n## Unreleased\n\n- Share order is kept (#63)\n\n## 2026.09.04\n\n- Old\n")
    run("seed", "--changelog", changelog, "--carry-from", old, "--since", "2026.09.04", "--repo", repo)
    body = pr.load_changelog(changelog).unreleased().bullets()
    assert body[0] == "- Share order is kept (#63)"
    assert "- feat: new thing" in body and "- fix(ui): keep share order (#63)" in body
    run("seed", "--changelog", changelog, "--since", "2026.09.04", "--repo", repo)
    assert pr.load_changelog(changelog).unreleased().bullets() == body


def test_seed_carry_keeps_the_headings_that_are_not_versions(repo):
    """Carrying a release PR's notes forward must not drop the history's verbatim headings."""
    changelog = repo / "CHANGELOG.md"
    changelog.write_text("# Changelog\n\n## 2026.09.04\n\n- Old\n\n## 2024-06-30\n\n- Dashed\n\n"
                         "##  See previous releases for earlier notes...\n")
    old = repo / "old.md"
    old.write_text("# Changelog\n\n## Unreleased\n\n- Pending\n\n## 2026.09.04\n\n- Old\n")
    before = changelog.read_text()
    run("seed", "--changelog", changelog, "--carry-from", old, "--since", "HEAD", "--repo", repo)
    assert changelog.read_text() == "# Changelog\n\n## Unreleased\n\n- Pending\n\n" + before.split("\n\n", 1)[1]


def test_seed_from_beta_sections_stops_at_last_stable(tmp_path):
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(
        "# Changelog\n\n## 2026.09.06b (beta)\n\n- Newer beta\n\n## 2026.09.06a (beta)\n\n- Older beta\n- Shared\n\n"
        "## 2026.09.01\n\n- Stable\n\n## 2026.08.30a (beta)\n\n- Ancient beta\n"
    )
    run("seed", "--changelog", changelog, "--beta-sections")
    assert pr.load_changelog(changelog).unreleased().bullets() == ["- Older beta", "- Shared", "- Newer beta"]


def test_next_version_stable_is_the_bare_date_unless_taken_and_betas_take_letters(repo):
    """A same-day beta must not push the stable to a letter; only a second stable that day takes one."""
    sh = lambda *a: subprocess.run(["git", *a], cwd=repo, check=True, capture_output=True)  # noqa: E731
    assert pr.next_version(repo, "stable", "2026.09.05") == "2026.09.05"
    assert pr.next_version(repo, "beta", "2026.09.05") == "2026.09.05a"
    sh("tag", "2026.09.05a")
    sh("tag", "2026.09.05.1200")
    sh("tag", "pr-3-2026.09.05.0260905101010")
    assert pr.next_version(repo, "beta", "2026.09.05") == "2026.09.05b"
    assert pr.next_version(repo, "stable", "2026.09.05") == "2026.09.05"
    sh("tag", "2026.09.05b")
    sh("tag", "2026.09.05")
    assert pr.next_version(repo, "stable", "2026.09.05") == "2026.09.05c"
    assert pr.next_version(repo, "beta", "2026.09.05") == "2026.09.05c"
    assert pr.next_version(repo, "stable", "2026.09.04") == "2026.09.04a"
    sh("tag", "2026.09.07.1200")
    assert pr.next_version(repo, "beta", "2026.09.07") == "2026.09.07a", "an old .HHMM tag is not a letter release"
    sh("tag", "2026.09.06z")
    with pytest.raises(pr.ChangelogError):
        pr.next_version(repo, "beta", "2026.09.06")


def test_since_ref_prefers_the_channels_last_release_tag(repo):
    sh = lambda *a: subprocess.run(["git", *a], cwd=repo, check=True, capture_output=True)  # noqa: E731
    log = pr.parse_changelog("# Changelog\n\n## 2026.09.06a (beta)\n\n- b\n\n## 2026.09.04\n\n- s\n")
    assert pr.since_ref(repo, log, "stable") == "2026.09.04"
    assert pr.since_ref(repo, log, "beta") == "2026.09.04", "an untagged newer section falls through"
    sh("tag", "2026.09.06a", "HEAD~2")
    assert pr.since_ref(repo, log, "beta") == "2026.09.06a"
    sh("tag", "pr-9-2026.09.06a.0260906101010", "HEAD")
    none = pr.parse_changelog("# Changelog\n\n## 2025.01.01\n\n- s\n")
    assert pr.since_ref(repo, none, "stable") == "2026.09.06a", "the nearest release tag, never a test build's"


def test_seed_does_not_carry_bullets_that_already_shipped(repo):
    """release/<channel> outlives its cut, so its Unreleased may hold bullets a released section now carries."""
    changelog = repo / "CHANGELOG.md"
    changelog.write_text("# Changelog\n\n## 2026.09.05\n\n- Shipped in the cut\n\n## 2026.09.04\n\n- Old\n")
    old = repo / "old.md"
    old.write_text("# Changelog\n\n## Unreleased\n\n- Shipped in the cut\n- Still pending\n\n## 2026.09.04\n\n- Old\n")
    run("seed", "--changelog", changelog, "--carry-from", old, "--since", "HEAD", "--repo", repo)
    assert pr.load_changelog(changelog).unreleased().bullets() == ["- Still pending"]


def test_cut_retires_the_release_branch_only_after_the_base_push():
    """A surviving release/<channel> would carry its released bullets into the next release PR."""
    body = (SCRIPTS / "plg_release_cut.sh").read_text()
    push, disarm, delete = (body.index(t) for t in
                            ('git push -q origin "HEAD:$BASE"', "trap - ERR", 'git push -q origin --delete "release/$CHANNEL"'))
    assert push < disarm < delete, "the branch goes only once the release is fully published"


def test_merge_changelog_inserts_missing_sections_and_keeps_our_order(tmp_path):
    ours = tmp_path / "ours.md"
    theirs = tmp_path / "theirs.md"
    out = tmp_path / "out.md"
    ours.write_text("# Changelog\n\nPreamble\n\n## Unreleased\n\n- Draft\n\n## 2026.09.06\n\n- Stable six\n\n"
                    "## 2026.09.01\n\n- One\n\n## 2026.09.03\n\n- Historic out-of-order block\n\n## 2024-06-30\n\n- Dashed\n")
    theirs.write_text("# Changelog\n\n## 2026.09.06a (beta)\n\n- Beta six a\n\n## 2026.09.02 (beta)\n\n- Two\n\n"
                      "## 2026.09.01\n\n- One (beta copy)\n\n## 2024-06-30\n\n- Dashed (their copy)\n")
    run("merge-changelog", "--ours", ours, "--theirs", theirs, "--out", out)
    log = pr.load_changelog(out)
    assert [s.version for s in log.sections] == [
        "Unreleased", "2026.09.06a", "2026.09.06", "2026.09.02", "2026.09.01", "2026.09.03", "2024-06-30"]
    assert log.find("2026.09.01").body == ["- One"]
    assert log.sections[-1].body == ["- Dashed"]
    assert log.find("2026.09.06a").beta is True
    assert log.preamble == ["Preamble"]


def test_last_version_and_entity(plg):
    p, changelog = plg
    run("migrate", "--plg", p, "--changelog", changelog)
    changelog.write_text(changelog.read_text().replace("## 2026.08.28\n", "## 2026.08.28 (beta)\n"))
    assert pr.load_changelog(changelog).released("stable")[0].version == "2026.08.14"
    assert pr.load_changelog(changelog).released("beta")[0].version == "2026.08.28"
    assert run("last-version", "--changelog", changelog, "--channel", "stable") == 0
    assert run("entity", "--plg", p, "--name", "pluginURL") == 0
    assert pr.plg_entities(p.read_text())["pluginURL"] == (
        "https://raw.githubusercontent.com/someone/ca.mover.tuning/beta/plugins/ca.mover.tuning.plg")
    assert run("entity", "--plg", p, "--name", "nope") == 2


RELEASES = ('[{"tagName":"pr-12-2026.09.20.0260920101010","isPrerelease":true},'
            '{"tagName":"2026.09.20b","isPrerelease":true},'
            '{"tagName":"2026.09.19","isPrerelease":false},'
            '{"tagName":"2026.09.18a","isPrerelease":true},'
            '{"tagName":"2026.09.07","isPrerelease":false}]')


def _rollback_footer(tmp_path, gh_body, channel="stable", plgr_body="echo upgrade=minor", call="rollback_footer"):
    """Run rollback_footer from plg_release_cut.sh against a stub gh and a stub release helper."""
    body = (SCRIPTS / "plg_release_cut.sh").read_text()
    fn = re.search(r"^rollback_footer\(\) \{.*?^\}", body, re.M | re.S).group(0)
    bindir = tmp_path / "bin"
    bindir.mkdir(exist_ok=True)
    for name, text in (("gh", gh_body), ("plgr", plgr_body)):
        (bindir / name).write_text("#!/bin/bash\n" + text + "\n")
        (bindir / name).chmod(0o755)
    env = {**os.environ, "PATH": f"{bindir}:{os.environ['PATH']}", "GITHUB_REPOSITORY": "someone/plugin",
           "PLG": "plugins/plugin.plg", "CHANNEL": channel, "PLGR": str(bindir / "plgr"),
           "STABLE_PLUGIN_URL": "https://raw.githubusercontent.com/someone/plugin/master/plugins/plugin.plg"}
    return subprocess.run(["bash", "-c", f"set -euo pipefail\n{fn}\n{call}"], cwd=tmp_path, env=env,
                          capture_output=True, text=True)


def _gh_listing(releases=RELEASES):
    """A gh stub that applies the script's own --jq filter to a canned release listing."""
    return ('while [ $# -gt 0 ]; do [ "$1" = --jq ] && { f="$2"; break; }; shift; done\n'
            f"jq -r \"$f\" <<'JSON'\n{releases}\nJSON")


def test_stable_rollback_pins_the_previous_stable_release(tmp_path):
    r = _rollback_footer(tmp_path, _gh_listing())
    assert r.returncode == 0, r.stderr
    lines = r.stdout.splitlines()
    assert "plugin install https://raw.githubusercontent.com/someone/plugin/2026.09.19/plugins/plugin.plg forced" in lines
    assert "[2026.09.19](https://github.com/someone/plugin/releases/tag/2026.09.19)" in r.stdout
    assert "your settings are kept" in r.stdout and "Auto Update Applications" in r.stdout
    assert "test mode" not in r.stdout


def test_beta_rollback_pins_the_previous_beta_and_offers_the_way_back_to_stable(tmp_path):
    r = _rollback_footer(tmp_path, _gh_listing(), channel="beta")
    assert r.returncode == 0, r.stderr
    lines = r.stdout.splitlines()
    assert "plugin install https://raw.githubusercontent.com/someone/plugin/2026.09.20b/plugins/plugin.plg forced" in lines
    assert "plugin install https://raw.githubusercontent.com/someone/plugin/master/plugins/plugin.plg forced" in lines
    assert "pr-12" not in r.stdout, "a PR test build is a pre-release but never a beta release"


def test_first_beta_offers_only_the_way_back_to_stable(tmp_path):
    r = _rollback_footer(tmp_path, _gh_listing('[{"tagName":"2026.09.19","isPrerelease":false}]'), channel="beta")
    assert r.returncode == 0, r.stderr
    assert "Roll back" not in r.stdout and "go back to the stable release" in r.stdout


def test_no_rollback_note_before_the_first_stable_release(tmp_path):
    r = _rollback_footer(tmp_path, _gh_listing("[]"))
    assert (r.returncode, r.stdout) == (0, "")


def test_rollback_to_a_major_release_warns_about_test_mode(tmp_path):
    r = _rollback_footer(tmp_path, _gh_listing(), plgr_body="echo upgrade=major")
    assert r.returncode == 0, r.stderr
    assert "turns test mode on" in r.stdout


def test_an_unexpected_tag_never_reaches_the_pasted_command(tmp_path):
    """The stub bypasses the listing filter; the script's own shape check must still refuse the tag."""
    r = _rollback_footer(tmp_path, "echo 'v1;touch INJECTED;#'", call='rollback=$(rollback_footer); echo reached')
    assert r.returncode != 0 and "reached" not in r.stdout
    assert not (tmp_path / "INJECTED").exists()


@pytest.mark.parametrize("gh_body,plgr_body", [
    ("echo 'HTTP 502' >&2; exit 1", "echo upgrade=minor"),  # the release lookup failed
    (_gh_listing(), "echo 'HTTP Error 404' >&2; exit 2"),  # the rollback target no longer installs
])
def test_a_rollback_note_that_cannot_be_made_right_stops_the_release(tmp_path, gh_body, plgr_body):
    r = _rollback_footer(tmp_path, gh_body, plgr_body=plgr_body, call='rollback=$(rollback_footer); echo reached')
    assert r.returncode != 0 and "reached" not in r.stdout


def test_the_committed_manifest_is_what_the_changelog_renders():
    """The repository's own history must survive a parse and render unchanged."""
    plg_path = REPO / "plugins" / "ca.mover.tuning.plg"
    text = plg_path.read_text(encoding="utf-8")
    branch = pr.PLUGIN_URL_BRANCH_RE.match(pr.plg_entities(text)["pluginURL"]).group("branch")
    channel = "beta" if branch == "beta" else "stable"
    log = pr.load_changelog(REPO / "CHANGELOG.md")
    assert pr.changes_diff(plg_path, log, channel) is None
    _, content, _ = pr.split_plg(text)
    assert pr.render_changes(pr.parse_changes(content), channel) == content
