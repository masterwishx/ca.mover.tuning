import hashlib
import json
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


def _named_steps():
    import yaml

    wf = yaml.safe_load((REPO / ".github/workflows/release.yml").read_text())
    return {s.get("name"): s for s in wf["jobs"]["release"]["steps"]}


def test_the_release_job_works_from_the_branch_tip():
    """A queued or re-run job's event commit can be behind its branch, and a cut from it cannot push."""
    assert _named_steps()["Checkout"]["with"]["ref"] == "${{ github.ref }}"


def test_release_scripts_are_staged_from_the_commit_the_run_started_from(tmp_path):
    """GitHub read this workflow at the event commit; the tip's scripts may belong to a newer one."""
    repo = tmp_path / "repo"
    scripts = repo / ".github/scripts/release"
    scripts.mkdir(parents=True)
    _git(repo, "init", "-q", "-b", "master")
    shas = []
    for text in ("started", "tip"):
        (scripts / "plg_release_cut.sh").write_text(text)
        _git(repo, "add", "-A")
        _git(repo, "-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-qm", text)
        shas.append(_git(repo, "rev-parse", "HEAD"))
    runner_temp, env_file = tmp_path / "runner", tmp_path / "env"
    runner_temp.mkdir()
    env = {**os.environ, "GITHUB_SHA": shas[0], "RUNNER_TEMP": str(runner_temp), "GITHUB_ENV": str(env_file)}
    subprocess.run(["bash", "-c", _named_steps()["Stage the release scripts"]["run"]], cwd=repo, env=env,
                   check=True, capture_output=True)
    assert (runner_temp / "release/plg_release_cut.sh").read_text() == "started"
    assert env_file.read_text() == f"SCRIPTS={runner_temp}/release\n"


def test_cross_channel_refreshes_wait_for_the_other_channels_merged_release():
    """A refresh while that channel's merged release awaits its cut would reopen the released notes as a new PR."""
    steps = _named_steps()
    for name in ("Refresh stable release PR after a beta", "Refresh beta release PR after a stable"):
        assert "steps.decide.outputs.other_pr == ''" in steps[name]["if"], name


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


def _run_decide(tmp_path, repo, mode, gh_body, ref_name="master", event=None):
    """Run the workflow's 'Decide channel and mode' step against a stub gh."""
    bindir = tmp_path / "bin"
    bindir.mkdir(exist_ok=True)
    (bindir / "gh").write_text("#!/bin/bash\n" + gh_body + "\n")
    (bindir / "gh").chmod(0o755)
    out = tmp_path / "out.txt"
    out.write_text("")
    env = {**os.environ, "PATH": f"{bindir}:{os.environ['PATH']}", "MODE_IN": mode, "GITHUB_REF_NAME": ref_name,
           "STABLE_BRANCH": "master", "BETA_BRANCH": "beta", "GITHUB_OUTPUT": str(out),
           "GITHUB_REPOSITORY": "someone/plugin", "DISPATCH_TOKEN": "dispatch-token"}
    env.pop("GITHUB_EVENT_NAME", None)
    if event:
        env["GITHUB_EVENT_NAME"] = event
    r = subprocess.run(["bash", "-c", _step("decide")], cwd=repo, env=env, capture_output=True, text=True)
    return r, dict(line.split("=", 1) for line in out.read_text().splitlines())


@pytest.mark.parametrize("mode", ["relase", "", "RELEASE", "release; rm -rf /"])
def test_decide_rejects_an_unsupported_mode(tmp_path, decide_repo, mode):
    r, _ = _run_decide(tmp_path, decide_repo[0], mode, "exit 0")
    assert r.returncode == 1, r.stdout
    assert "mode must be auto, pr or release" in r.stdout + r.stderr


@pytest.mark.parametrize("mode", ["pr", "release"])
def test_decide_takes_an_explicit_mode_as_given(tmp_path, decide_repo, mode):
    r, out = _run_decide(tmp_path, decide_repo[0], mode, "echo ' '")
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


def test_decide_stops_on_a_release_tag_the_branch_does_not_have(tmp_path, decide_repo):
    """The cut moves the branch last: a tag the branch lacks is a cut that stopped part way, not a release."""
    repo, merged = decide_repo
    gh = f"echo '7 {merged}'"

    def tag_off_the_branch(tag):
        _git(repo, "switch", "-q", "--detach", "master")
        _git(repo, "commit", "-q", "--allow-empty", "-m", f"chore(release): {tag}")
        _git(repo, "tag", tag)
        _git(repo, "switch", "-q", "master")

    tag_off_the_branch("2026.09.26")
    r, out = _run_decide(tmp_path, repo, "auto", gh)
    assert r.returncode != 0 and "mode" not in out
    assert "gh release delete 2026.09.26 --cleanup-tag --yes" in r.stderr and "stopped part way" in r.stderr
    _git(repo, "merge", "-q", "--ff-only", "2026.09.26")
    tag_off_the_branch("2026.09.27")
    assert _run_decide(tmp_path, repo, "auto", gh)[1]["mode"] == "pr", "one release tag on the branch is enough"


def test_decide_releases_when_only_the_other_channels_tag_contains_the_merge(tmp_path, decide_repo):
    """master merged into beta before the stable cut ran: the beta release's tag contains the stable merge."""
    repo, merged = decide_repo
    _git(repo, "switch", "-q", "-c", "beta", "HEAD~2")
    _git(repo, "merge", "-q", "--no-ff", "-m", "Merge branch 'master' into beta", "master")
    _git(repo, "commit", "-q", "--allow-empty", "-m", "Merge pull request #9 from someone/release/beta")
    _git(repo, "commit", "-q", "--allow-empty", "-m", "chore(release): 2026.09.26 [skip ci]")
    _git(repo, "tag", "2026.09.26")
    _git(repo, "switch", "-q", "master")
    r, out = _run_decide(tmp_path, repo, "auto", f"echo '7 {merged}'")
    assert r.returncode == 0, r.stderr
    assert (out["mode"], out["pr_number"]) == ("release", "7")


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
    assert run("seed", "--changelog", changelog, "--channel", "beta", "--since", "does-not-exist", "--repo", tmp_path) == 2
    err = capsys.readouterr().err
    assert "not a git repository" in err.lower() or "unknown revision" in err.lower()


def test_execution_errors_exit_2_not_1(tmp_path):
    missing = tmp_path / "nope.md"
    p = tmp_path / "nope.plg"
    assert run("check", "--changelog", missing, "--plg", p, "--channel", "stable", "--branch", "master") == 2
    assert run("next-version", "--channel", "stable", "--tz", "Mars/Olympus", "--repo", tmp_path) == 2


@pytest.mark.parametrize("old,new", [
    ('"https://raw.githubusercontent.com/&github;/beta/plugins/&name;.plg"', '"https://example.invalid/&name;.plg"'),
    ('"0123456789abcdef0123456789abcdef"', '"not-a-digest"'),
    ('<!ENTITY version   "2026.08.28">', '<!ENTITY version   "2026.08.29">'),
])
def test_check_refuses_a_manifest_the_changelog_or_branch_does_not_back(plg, old, new):
    p, changelog = plg
    run("migrate", "--plg", p, "--changelog", changelog)
    args = ("check", "--changelog", changelog, "--plg", p, "--channel", "beta", "--branch", "beta")
    assert run(*args) == 0
    p.write_text(p.read_text().replace(old, new, 1))
    assert run(*args) == 1


def test_require_nonempty_needs_bullets_in_unreleased(plg):
    p, changelog = plg
    run("migrate", "--plg", p, "--changelog", changelog)
    args = ("check", "--changelog", changelog, "--plg", p, "--channel", "beta", "--branch", "beta", "--require-nonempty")
    assert run(*args) == 1, "no Unreleased section"
    text = changelog.read_text()
    changelog.write_text(text.replace("\n## 2026.08.28\n", "\n## Unreleased\n\n## 2026.08.28\n", 1))
    assert run(*args) == 1, "an Unreleased section without bullets"
    changelog.write_text(text.replace("\n## 2026.08.28\n", "\n## Unreleased\n\n- A note\n\n## 2026.08.28\n", 1))
    assert run(*args) == 0


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
    run("seed", "--changelog", changelog, "--channel", "beta", "--carry-from", old, "--since", "2026.09.04", "--repo", repo)
    body = pr.load_changelog(changelog).unreleased().bullets()
    assert body[0] == "- Share order is kept (#63)"
    assert "- feat: new thing" in body and "- fix(ui): keep share order (#63)" in body
    run("seed", "--changelog", changelog, "--channel", "beta", "--since", "2026.09.04", "--repo", repo)
    assert pr.load_changelog(changelog).unreleased().bullets() == body


def test_seed_carry_keeps_the_headings_that_are_not_versions(repo):
    """Carrying a release PR's notes forward must not drop the history's verbatim headings."""
    changelog = repo / "CHANGELOG.md"
    changelog.write_text("# Changelog\n\n## 2026.09.04\n\n- Old\n\n## 2024-06-30\n\n- Dashed\n\n"
                         "##  See previous releases for earlier notes...\n")
    old = repo / "old.md"
    old.write_text("# Changelog\n\n## Unreleased\n\n- Pending\n\n## 2026.09.04\n\n- Old\n")
    before = changelog.read_text()
    run("seed", "--changelog", changelog, "--channel", "beta", "--carry-from", old, "--since", "HEAD", "--repo", repo)
    assert changelog.read_text() == "# Changelog\n\n## Unreleased\n\n- Pending\n\n" + before.split("\n\n", 1)[1]


def test_seed_from_beta_sections_stops_at_last_stable(tmp_path):
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text(
        "# Changelog\n\n## 2026.09.06b (beta)\n\n- Newer beta\n\n## 2026.09.06a (beta)\n\n- Older beta\n- Shared\n\n"
        "## 2026.09.01\n\n- Stable\n\n## 2026.08.30a (beta)\n\n- Ancient beta\n"
    )
    run("seed", "--changelog", changelog, "--channel", "stable", "--beta-sections")
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
    run("seed", "--changelog", changelog, "--channel", "stable", "--carry-from", old, "--since", "HEAD", "--repo", repo)
    assert pr.load_changelog(changelog).unreleased().bullets() == ["- Still pending"]


def test_cut_retires_the_release_branch_only_after_the_base_push():
    """A surviving release/<channel> would carry its released bullets into the next release PR."""
    body = (SCRIPTS / "plg_release_cut.sh").read_text()
    delete = 'git push -q --force-with-lease="refs/heads/release/$CHANNEL:$merged_head" origin ":refs/heads/release/$CHANNEL"'
    push, disarm, gone = (body.index(t) for t in ('git push -q origin "HEAD:$BASE"', "trap - ERR", delete))
    assert push < disarm < gone, "the branch goes only once the release is fully published"


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


RELEASES = ('[{"tag_name":"2026.09.21","prerelease":false,"draft":true},'
            '{"tag_name":"pr-12-2026.09.20.0260920101010","prerelease":true,"draft":false},'
            '{"tag_name":"2026.09.20b","prerelease":true,"draft":false},'
            '{"tag_name":"2026.09.19","prerelease":false,"draft":false},'
            '{"tag_name":"2026.09.18a","prerelease":true,"draft":false},'
            '{"tag_name":"2026.09.07","prerelease":false,"draft":false}]')


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


def _gh_listing(*pages):
    """A gh stub that applies the script's own --jq filter to each page of a canned release listing."""
    body = 'all=""\nwhile [ $# -gt 0 ]; do case "$1" in --jq) f="$2"; shift ;; --paginate) all=1 ;; esac; shift; done\n'
    for n, page in enumerate(pages or (RELEASES,)):
        body += ('[ -n "$all" ] || exit 0\n' if n else "") + f"jq -r \"$f\" <<'JSON'\n{page}\nJSON\n"
    return body


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
    r = _rollback_footer(tmp_path, _gh_listing('[{"tag_name":"2026.09.19","prerelease":false,"draft":false}]'),
                         channel="beta")
    assert r.returncode == 0, r.stderr
    assert "Roll back" not in r.stdout and "go back to the stable release" in r.stdout


def test_rollback_note_finds_the_previous_release_past_the_first_page(tmp_path):
    """A run of betas can push the last stable release off the first page of the listing."""
    betas = json.dumps([{"tag_name": f"2026.09.{n // 26 + 20}{chr(97 + n % 26)}", "prerelease": True, "draft": False}
                        for n in range(99, -1, -1)])
    r = _rollback_footer(tmp_path, _gh_listing(betas, RELEASES))
    assert r.returncode == 0, r.stderr
    assert "plugin install https://raw.githubusercontent.com/someone/plugin/2026.09.19/plugins/plugin.plg forced" in r.stdout.splitlines()


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


@pytest.mark.parametrize("channel,gh_body,plgr_body", [
    ("stable", "echo 'HTTP 502' >&2; exit 1", "echo upgrade=minor"),  # the release lookup failed
    ("stable", _gh_listing(), "echo 'HTTP Error 404' >&2; exit 2"),  # the rollback target no longer installs
    ("beta", _gh_listing(), 'case "$*" in *"/master/"*) echo "HTTP Error 404" >&2; exit 2 ;; esac; echo upgrade=minor'),
])
def test_a_rollback_note_that_cannot_be_made_right_stops_the_release(tmp_path, channel, gh_body, plgr_body):
    r = _rollback_footer(tmp_path, gh_body, channel=channel, plgr_body=plgr_body,
                         call='rollback=$(rollback_footer); echo reached')
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


def _manifest(branch="master", version="2026.09.19", md5="0" * 32, install="chmod 644 /usr/local/sbin/x"):
    return (
        "<?xml version='1.0' standalone='yes'?>\n<!DOCTYPE PLUGIN [\n"
        '<!ENTITY name      "p">\n'
        f'<!ENTITY version   "{version}">\n'
        f'<!ENTITY md5       "{md5}">\n'
        f'<!ENTITY pluginURL "https://raw.githubusercontent.com/someone/&name;/{branch}/plugins/&name;.plg">\n'
        ']>\n<PLUGIN name="&name;" version="&version;" pluginURL="&pluginURL;">\n'
        f"<CHANGES>\n###{version}\n- Notes for {version}\n\n</CHANGES>\n"
        f'<FILE Run="/bin/bash">\n<INLINE>\n{install}\necho step one\necho step two\necho installed\n</INLINE>\n</FILE>\n</PLUGIN>\n'
    )


def test_merge_manifest_takes_the_other_branch_installer_and_keeps_our_release_fields():
    base = _manifest()
    ours = _manifest(version="2026.09.20", md5="a" * 32)
    theirs = _manifest(branch="beta", version="2026.09.21a", md5="b" * 32, install="chmod 755 /usr/local/sbin/x")
    merged = pr.merge_manifest(base, ours, theirs)
    assert "chmod 755 /usr/local/sbin/x" in merged
    assert pr.plg_entities(merged) | {"name": "p"} == pr.plg_entities(ours) | {"name": "p"}
    assert pr.split_plg(merged)[1] == [], "CHANGES is left for render"


def test_merge_manifest_keeps_an_installer_fix_made_on_our_side():
    base = _manifest(branch="beta", version="2026.09.21a")
    ours = _manifest(branch="beta", version="2026.09.22a", install="chmod 755 /usr/local/sbin/x")
    theirs = _manifest(version="2026.09.21", md5="c" * 32)
    merged = pr.merge_manifest(base, ours, theirs)
    assert "chmod 755 /usr/local/sbin/x" in merged
    assert pr.plg_entities(merged)["version"] == "2026.09.22a"
    assert "/beta/plugins/" in pr.plg_entities(merged)["pluginURL"]


def test_merge_manifest_refuses_both_branches_changing_the_same_installer_line(tmp_path):
    base = _manifest()
    ours = _manifest(install="chmod 700 /usr/local/sbin/x")
    theirs = _manifest(branch="beta", install="chmod 755 /usr/local/sbin/x")
    with pytest.raises(pr.ChangelogError):
        pr.merge_manifest(base, ours, theirs)
    files = []
    for name, text in (("base", base), ("ours", ours), ("theirs", theirs)):
        (tmp_path / name).write_text(text)
        files += [f"--{name}", tmp_path / name]
    assert run("merge-manifest", *files, "--out", tmp_path / "out") == 2


def test_last_beta_is_the_newest_beta_release(tmp_path, capsys):
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text("# Changelog\n\n## 2026.09.21\n\n- s\n\n## 2026.09.20b (beta)\n\n- b\n\n"
                         "## 2026.09.22a (beta)\n\n- newest\n\n## 2026.09.20a (beta)\n\n- a\n")
    assert run("last-beta", "--changelog", changelog) == 0
    assert capsys.readouterr().out.strip() == "2026.09.22a"
    changelog.write_text("# Changelog\n\n## 2026.09.21\n\n- s\n")
    assert run("last-beta", "--changelog", changelog) == 0
    assert capsys.readouterr().out == ""


def test_stable_refresh_keeps_edits_and_adds_only_newer_betas(tmp_path):
    """Released beta notes are not shipped on the stable channel, so the stable PR's edits and deletions stand."""
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text("# Changelog\n\n## 2026.09.22a (beta)\n\n- Four\n\n"
                         "## 2026.09.21a (beta)\n\n- One\n- Two\n- Three\n\n## 2026.09.19\n\n- Old\n")
    old = tmp_path / "old.md"
    old.write_text("# Changelog\n\n## Unreleased\n\n- One, reworded\n- Three\n\n## 2026.09.19\n\n- Old\n")
    run("seed", "--changelog", changelog, "--channel", "stable", "--carry-from", old,
        "--beta-sections", "--beta-after", "2026.09.21a")
    assert pr.load_changelog(changelog).unreleased().bullets() == ["- One, reworded", "- Three", "- Four"]


def test_promotion_seeds_master_commits_beside_the_beta_notes(repo):
    changelog = repo / "CHANGELOG.md"
    changelog.write_text("# Changelog\n\n## 2026.09.05a (beta)\n\n- Beta note\n\n## 2026.09.04\n\n- Old\n")
    run("seed", "--changelog", changelog, "--channel", "stable", "--beta-sections",
        "--since", "2026.09.04", "--until", "HEAD", "--repo", repo)
    bullets = pr.load_changelog(changelog).unreleased().bullets()
    assert bullets[0] == "- Beta note" and "- feat: new thing" in bullets


def test_seed_skips_commits_that_only_edit_the_changelog(repo):
    sh = lambda *a: subprocess.run(["git", *a], cwd=repo, check=True, capture_output=True)  # noqa: E731
    changelog = repo / "CHANGELOG.md"
    changelog.write_text("# Changelog\n\n## 2026.09.04\n\n- Old\n")
    sh("add", "CHANGELOG.md")
    sh("commit", "-qm", "Update CHANGELOG.md")
    changelog.write_text(changelog.read_text() + "\n")
    (repo / "f").write_text("both")
    sh("commit", "-qam", "Plain change with notes")
    subjects = [b.split(" (")[0] for b in pr.commit_bullets(repo, "2026.09.04", "HEAD", changelog)]
    assert "- Update CHANGELOG.md" not in subjects and "- Plain change with notes" in subjects


def test_heading_suffix_is_escaped_in_the_manifest(tmp_path):
    changelog = tmp_path / "CHANGELOG.md"
    changelog.write_text("# Changelog\n\n## 2026.09.26 - Fixes & <tweaks>\n\n- x\n")
    content = pr.render_changes(pr.load_changelog(changelog), "stable")
    assert content[0] == "###2026.09.26 - Fixes &amp; &lt;tweaks>"
    assert pr.parse_changes(content).sections[0].rest == " - Fixes & <tweaks>"


def test_decide_restarts_the_other_channels_waiting_release(tmp_path, decide_repo):
    """A push to one branch can cancel the other branch's queued release run; the push's run starts it again."""
    repo, merged = decide_repo
    _git(repo, "tag", "2026.09.26", "HEAD")
    _git(repo, "switch", "-q", "-c", "beta", "HEAD~2")
    (repo / "f").write_text("beta release PR merge")
    _git(repo, "commit", "-qam", "Merge pull request #9 from someone/release/beta")
    beta_merged = _git(repo, "rev-parse", "HEAD")
    _git(repo, "update-ref", "refs/remotes/origin/beta", beta_merged)
    _git(repo, "switch", "-q", "master")
    gh = ('case "$*" in\n  *"release/stable"*) echo "7 ' + merged + '" ;;\n  *"release/beta"*) echo "9 ' + beta_merged + '" ;;\n'
          '  *"workflow run"*) echo "$GH_TOKEN $*" >> dispatched ;;\nesac')
    r, out = _run_decide(tmp_path, repo, "auto", gh, event="push")
    assert r.returncode == 0, r.stderr
    assert (out["mode"], out["other_pr"]) == ("pr", "9")
    dispatched = (repo / "dispatched").read_text()
    assert dispatched.startswith("dispatch-token workflow run release.yml") and "--ref beta" in dispatched
    (repo / "dispatched").unlink()
    out = _run_decide(tmp_path, repo, "release", gh, event="workflow_dispatch")[1]
    assert out["other_pr"] == "9", "a release run still learns the other channel is waiting"
    assert not (repo / "dispatched").exists(), "a started run never starts another"


def test_decide_stops_when_the_other_channels_lookup_fails(tmp_path, decide_repo):
    repo, merged = decide_repo
    gh = 'case "$*" in\n  *"release/stable"*) echo " " ;;\n  *) echo "HTTP 502" >&2; exit 1 ;;\nesac'
    r, out = _run_decide(tmp_path, repo, "auto", gh, event="push")
    assert r.returncode != 0 and "mode" not in out


class Channels:
    """A bare origin with master and beta, driven through the real release scripts."""

    PLG = "plugins/p.plg"

    def __init__(self, tmp):
        self.tmp, self.origin, self.work, self.user = tmp, tmp / "origin.git", tmp / "work", tmp / "user"
        bindir = tmp / "bin"
        bindir.mkdir()
        (bindir / "gh").write_text('#!/bin/bash\necho "gh $*" >> "' + str(tmp / "gh.log") + '"\n')
        (bindir / "gh").chmod(0o755)
        ident = {f"GIT_{who}_{what}": val for who in ("AUTHOR", "COMMITTER") for what, val in (("NAME", "t"), ("EMAIL", "t@example.com"))}
        self.env = {**os.environ, **ident, "PATH": f"{bindir}:{os.environ['PATH']}", "SCRIPTS": str(SCRIPTS),
                    "PLG": self.PLG, "CHANGELOG": "CHANGELOG.md", "GIT_USER": "t", "GIT_EMAIL": "t@example.com",
                    "BETA_BRANCH": "beta", "STABLE_BRANCH": "master", "DRY_RUN": "false"}
        for key in ("GH_TOKEN", "GITHUB_REPOSITORY"):
            self.env.pop(key, None)
        self.sh(tmp, "init", "-q", "--bare", "-b", "master", str(self.origin))
        self.sh(tmp, "clone", "-q", str(self.origin), str(self.user))
        self.sh(self.user, "switch", "-q", "-c", "master")
        (self.user / "plugins").mkdir()
        (self.user / "CHANGELOG.md").write_text("# Changelog\n\n## 2026.09.19\n\n- Old stable\n")
        self.write_manifest("master", "2026.09.19", "stable")
        (self.user / "f").write_text("0")
        self.sh(self.user, "add", "-A")
        self.sh(self.user, "commit", "-qm", "chore: initial")
        self.sh(self.user, "tag", "2026.09.19")
        self.sh(self.user, "push", "-q", "origin", "master", "--tags")
        self.sh(self.user, "switch", "-q", "-c", "beta")
        self.write_manifest("beta", "2026.09.19", "beta")
        self.sh(self.user, "commit", "-qam", "chore(beta): beta manifest")
        self.sh(self.user, "push", "-q", "origin", "beta")
        self.sh(tmp, "clone", "-q", str(self.origin), str(self.work))

    def sh(self, cwd, *args):
        return subprocess.run(["git", *args], cwd=cwd, env=self.env, check=True, capture_output=True, text=True).stdout

    def write_manifest(self, branch, version, channel, install="chmod 644 /usr/local/sbin/x"):
        plg = self.user / self.PLG
        plg.write_text(_manifest(branch, version, "0123456789abcdef0123456789abcdef", install))
        assert run("render", "--plg", plg, "--changelog", self.user / "CHANGELOG.md", "--channel", channel) == 0

    def on(self, branch):
        self.sh(self.user, "fetch", "-q", "origin", "--tags")
        self.sh(self.user, "switch", "-q", "-C", branch, f"origin/{branch}")

    def commit(self, branch, subject, path=None, edit=None):
        self.on(branch)
        target = self.user / (path or "src" / Path(re.sub(r"\W+", "-", subject)))
        target.parent.mkdir(exist_ok=True)
        target.write_text(edit(target.read_text()) if edit else subject)
        self.sh(self.user, "add", "-A")
        self.sh(self.user, "commit", "-qm", subject)
        self.sh(self.user, "push", "-q", "origin", branch)

    def release(self, branch, version, bullets, channel):
        """A release as the cut leaves it: a stamped section, CHANGES rendered, version set, tagged."""
        self.on(branch)
        cl = self.user / "CHANGELOG.md"
        head, rest = cl.read_text().split("\n## ", 1)
        marker = " (beta)" if channel == "beta" else ""
        cl.write_text(f"{head}\n## {version}{marker}\n\n{bullets}\n\n## {rest}")
        plg = self.user / self.PLG
        plg.write_text(re.sub(r'<!ENTITY version   "[^"]*"', f'<!ENTITY version   "{version}"', plg.read_text()))
        assert run("render", "--plg", plg, "--changelog", cl, "--channel", channel) == 0
        self.sh(self.user, "commit", "-qam", f"chore(release): {version} [skip ci]")
        self.sh(self.user, "tag", version)
        self.sh(self.user, "push", "-q", "origin", branch, "--tags")

    def merge_pr(self, head, base):
        self.on(base)
        self.sh(self.user, "merge", "-q", "--no-ff", "-m", f"Merge pull request from {head}", f"origin/{head}")
        self.sh(self.user, "push", "-q", "origin", base)

    def cut(self, branch, version, channel):
        """What the release job does to the branch after a release PR merges, short of building and publishing."""
        self.on(branch)
        cl, plg = self.user / "CHANGELOG.md", self.user / self.PLG
        assert run("stamp", "--changelog", cl, "--version", version, *(["--beta"] if channel == "beta" else [])) == 0
        plg.write_text(re.sub(r'<!ENTITY version   "[^"]*"', f'<!ENTITY version   "{version}"', plg.read_text()))
        assert run("render", "--plg", plg, "--changelog", cl, "--channel", channel) == 0
        self.sh(self.user, "commit", "-qam", f"chore(release): {version} [skip ci]")
        self.sh(self.user, "tag", version)
        self.sh(self.user, "push", "-q", "origin", branch, "--tags")

    def run(self, script, ok=True, **env):
        self.sh(self.work, "fetch", "-q", "origin", "--tags")
        self.sh(self.work, "reset", "-q", "--hard")
        self.sh(self.work, "checkout", "-q", "--detach", "origin/master")
        r = subprocess.run(["bash", str(SCRIPTS / script)], cwd=self.work, env={**self.env, **env},
                           capture_output=True, text=True)
        if not ok:
            return r
        assert r.returncode == 0, r.stdout + r.stderr
        return r.stdout

    def show(self, ref, path):
        self.sh(self.user, "fetch", "-q", "origin")
        return self.sh(self.user, "show", f"origin/{ref}:{path}")

    def check(self, ref, channel, branch):
        """The release check against a branch as origin has it."""
        plg, cl = self.tmp / f"{channel}.plg", self.tmp / f"{channel}.md"
        plg.write_text(self.show(ref, self.PLG))
        cl.write_text(self.show(ref, "CHANGELOG.md"))
        return run("check", "--changelog", cl, "--plg", plg, "--channel", channel, "--branch", branch)

    def unreleased(self, ref):
        return pr.parse_changelog(self.show(ref, "CHANGELOG.md")).unreleased().bullets()

    def log(self, rng):
        return self.sh(self.user, "log", "--no-merges", "--format=%s", rng).splitlines()


@pytest.fixture
def channels(tmp_path):
    return Channels(tmp_path)


def test_stable_pr_carries_an_urgent_master_fix_after_a_stable_release(channels):
    """Once a beta release is in stable and merged back, beta is always ahead; that alone is no promotion."""
    channels.commit("beta", "fix: beta fix")
    channels.release("beta", "2026.09.21a", "- Beta fix", "beta")
    channels.run("plg_release_pr.sh", CHANNEL="stable", BASE="master")
    channels.merge_pr("release/stable", "master")
    channels.cut("master", "2026.09.21", "stable")
    channels.run("plg_release_backmerge.sh", BASE="master", VERSION="2026.09.21")
    channels.commit("beta", "feat: unreleased beta work")
    channels.commit("master", "fix: urgent data-loss fix")
    out = channels.run("plg_release_pr.sh", CHANNEL="stable", BASE="master")
    assert "nothing to release" not in out
    assert channels.unreleased("release/stable") == ["- fix: urgent data-loss fix"]
    assert "feat: unreleased beta work" not in channels.log("origin/master..origin/release/stable")
    assert channels.check("release/stable", "stable", "master") == 0


def test_stable_pr_promotes_the_beta_release_not_unreleased_beta_work(channels):
    channels.commit("beta", "fix: beta fix one")
    channels.release("beta", "2026.09.21a", "- Beta fix one, reworded", "beta")
    channels.commit("beta", "feat: unreleased, untested beta work")
    channels.commit("master", "fix: urgent data-loss fix")
    channels.run("plg_release_pr.sh", CHANNEL="stable", BASE="master")
    assert channels.unreleased("release/stable") == ["- Beta fix one, reworded", "- fix: urgent data-loss fix"]
    brought = channels.log("origin/master..origin/release/stable")
    assert "fix: beta fix one" in brought and "feat: unreleased, untested beta work" not in brought


def test_stable_pr_lists_master_commits_already_in_the_beta_only_once(channels):
    """master merged into beta mid-cycle: the beta's notes describe those commits, so they are not listed again."""
    channels.commit("master", "fix: fixed on master first")
    channels.on("beta")
    channels.sh(channels.user, "merge", "-q", "--no-ff", "-m", "Merge master into beta", "origin/master")
    channels.sh(channels.user, "push", "-q", "origin", "beta")
    channels.release("beta", "2026.09.21a", "- The fix, described for users", "beta")
    channels.run("plg_release_pr.sh", CHANNEL="stable", BASE="master")
    assert channels.unreleased("release/stable") == ["- The fix, described for users"]


def test_stable_pr_edits_survive_the_next_beta_release(channels):
    channels.commit("beta", "fix: beta code change")
    channels.release("beta", "2026.09.21a", "- One\n- Two\n- Three", "beta")
    channels.run("plg_release_pr.sh", CHANNEL="stable", BASE="master")
    channels.commit("release/stable", "Update CHANGELOG.md", "CHANGELOG.md",
                    lambda t: t.replace("- One\n", "- One, reworded\n", 1).replace("- Two\n", "", 1))
    channels.release("beta", "2026.09.22a", "- Four", "beta")
    channels.run("plg_release_pr.sh", CHANNEL="stable", BASE="master")
    assert channels.unreleased("release/stable") == ["- One, reworded", "- Three", "- Four"]


def test_installer_changes_cross_between_the_channels(channels):
    channels.commit("beta", "fix: keep x executable after install", Channels.PLG,
                    lambda t: t.replace("chmod 644 /usr/local/sbin/x", "chmod 755 /usr/local/sbin/x"))
    channels.release("beta", "2026.09.21a", "- x stays executable", "beta")
    channels.run("plg_release_pr.sh", CHANNEL="stable", BASE="master")
    stable = channels.show("release/stable", Channels.PLG)
    assert "chmod 755 /usr/local/sbin/x" in stable
    assert pr.plg_entities(stable)["version"] == "2026.09.19" and "/master/plugins/" in pr.plg_entities(stable)["pluginURL"]
    assert channels.check("release/stable", "stable", "master") == 0
    channels.commit("master", "fix: log the install", Channels.PLG, lambda t: t.replace("echo installed", "echo installed ok"))
    channels.release("master", "2026.09.22", "- Install logs", "stable")
    channels.run("plg_release_backmerge.sh", BASE="master", VERSION="2026.09.22")
    beta = channels.show("beta", Channels.PLG)
    assert "echo installed ok" in beta and "chmod 755 /usr/local/sbin/x" in beta
    assert pr.plg_entities(beta)["version"] == "2026.09.21a" and "/beta/plugins/" in pr.plg_entities(beta)["pluginURL"]
    assert channels.check("beta", "beta", "beta") == 0


def test_release_scripts_leave_no_temporary_files(channels):
    """Each script keeps its files in one scratch directory and removes it when it exits."""
    scratch = channels.tmp / "scratch"
    scratch.mkdir()
    channels.release("beta", "2026.09.21a", "- Beta notes", "beta")
    channels.run("plg_release_pr.sh", CHANNEL="stable", BASE="master", TMPDIR=str(scratch))
    channels.sh(channels.user, "fetch", "-q", "origin")
    assert "merge 2026.09.21a into master" in channels.sh(channels.user, "log", "--format=%s", "origin/master..origin/release/stable")
    channels.release("master", "2026.09.22", "- Stable notes", "stable")
    channels.run("plg_release_backmerge.sh", BASE="master", VERSION="2026.09.22", TMPDIR=str(scratch))
    assert list(scratch.iterdir()) == []


@pytest.mark.parametrize("script", ["plg_release_pr.sh", "plg_release_cut.sh", "plg_release_backmerge.sh"])
def test_every_release_script_removes_its_scratch_directory(script):
    body = (SCRIPTS / script).read_text()
    assert "SCRATCH=$(mktemp -d)\ntrap 'rm -rf \"$SCRATCH\"' EXIT\n" in body
    assert body.count("mktemp") == 1, "temporary files go in $SCRATCH"


def test_beta_pr_edits_survive_a_refresh(channels):
    channels.commit("beta", "fix: A thing")
    channels.commit("beta", "Plain subject B")
    channels.run("plg_release_pr.sh", CHANNEL="beta", BASE="beta")
    channels.commit("release/beta", "Update CHANGELOG.md", "CHANGELOG.md",
                    lambda t: re.sub(r"- Plain subject B \([0-9a-f]+\)\n", "",
                                     t.replace("- fix: A thing\n", "- A thing is fixed for every share\n")))
    channels.commit("beta", "feat: C")
    channels.run("plg_release_pr.sh", CHANNEL="beta", BASE="beta")
    assert channels.unreleased("release/beta") == ["- A thing is fixed for every share", "- feat: C"]


def test_a_notes_only_edit_is_not_a_bullet_after_the_back_merge(channels):
    channels.commit("master", "Update CHANGELOG.md", "CHANGELOG.md", lambda t: t + "\n")
    channels.release("master", "2026.09.20", "- Stable twenty", "stable")
    channels.run("plg_release_backmerge.sh", BASE="master", VERSION="2026.09.20")
    channels.commit("beta", "fix: beta work")
    channels.run("plg_release_pr.sh", CHANNEL="beta", BASE="beta")
    assert channels.unreleased("release/beta") == ["- fix: beta work"]


def test_refresh_stops_rather_than_drop_a_code_change_on_the_release_pr(channels):
    """The rebuild carries over only the notes; anything else pushed to the release PR must not vanish silently."""
    channels.commit("beta", "fix: A thing")
    channels.run("plg_release_pr.sh", CHANNEL="beta", BASE="beta")
    channels.commit("release/beta", "Update p.plg", Channels.PLG, lambda t: t.replace("echo installed", "echo installed fine"))
    channels.commit("beta", "feat: C")
    r = channels.run("plg_release_pr.sh", ok=False, CHANNEL="beta", BASE="beta")
    assert r.returncode != 0 and Channels.PLG in r.stdout + r.stderr
    assert "echo installed fine" in channels.show("release/beta", Channels.PLG), "the edit is still on the PR"


def test_merge_manifest_reports_a_failed_merge_file_as_a_failure():
    """merge-file exits 255 when it cannot run (binary input); that is not a clash between the branches."""
    ours = _manifest(install="chmod 644 /usr/local/sbin/x\0")
    with pytest.raises(pr.ChangelogError, match="git merge-file failed: .*binary"):
        pr.merge_manifest(_manifest(), ours, _manifest(branch="beta"))


def test_merge_stops_when_git_refuses_to_merge(tmp_path):
    """An untracked file in the way makes git refuse without a conflict; nothing may be committed as if merged."""
    repo = tmp_path / "r"
    repo.mkdir()
    _git(repo, "init", "-q", "-b", "master")
    _git(repo, "config", "user.email", "t@example.com")
    _git(repo, "config", "user.name", "t")
    (repo / "p.plg").write_text(_manifest())
    (repo / "CHANGELOG.md").write_text("# Changelog\n\n## 2026.09.19\n\n- Notes for 2026.09.19\n")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-qm", "base")
    _git(repo, "switch", "-q", "-c", "other")
    (repo / "x").write_text("from other")
    _git(repo, "add", "x")
    _git(repo, "commit", "-qm", "add x")
    _git(repo, "switch", "-q", "master")
    (repo / "x").write_text("untracked, in the way")
    script = (f'set -euo pipefail\nPLG=p.plg CHANGELOG=CHANGELOG.md PLGR="python3 {SCRIPTS}/plg_release.py" SCRATCH="{tmp_path}"\n'
              f'. "{SCRIPTS}/plg_release_merge.sh"\nplg_merge other stable\n')
    r = subprocess.run(["bash", "-c", script], cwd=repo, capture_output=True, text=True)
    assert r.returncode != 0 and "could not merge other" in r.stdout + r.stderr


def test_decide_ignores_a_merged_pr_from_a_fork_with_the_release_branch_name(tmp_path, decide_repo):
    """Only the managed release branch cuts a release; a fork's branch of the same name is somebody's PR."""
    repo, merged = decide_repo
    listing = [{"number": 9, "isCrossRepository": True, "mergedAt": "2026-09-25T00:00:00Z", "mergeCommit": {"oid": merged}}]

    def gh(prs):
        return ('while [ $# -gt 0 ]; do [ "$1" = --jq ] && { f="$2"; break; }; shift; done\n'
                f"jq -r \"$f\" <<'JSON'\n{json.dumps(prs)}\nJSON")

    r, out = _run_decide(tmp_path, repo, "auto", gh(listing))
    assert r.returncode == 0, r.stderr
    assert out["mode"] == "pr"
    listing[0]["isCrossRepository"] = False
    assert _run_decide(tmp_path, repo, "auto", gh(listing))[1]["mode"] == "release"
