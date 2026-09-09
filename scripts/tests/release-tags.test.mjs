import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import { validateReleaseTag } from '../validate-release-tag.mjs';

test('each platform validates against its own version source', () => {
  const mac = fs.readFileSync('CITATION.cff', 'utf8').match(/^version:\s*(\S+)/m)[1];
  const win = fs.readFileSync('windows/Directory.Build.props', 'utf8').match(/<Version>([^<]+)<\/Version>/)[1];
  assert.equal(validateReleaseTag('macos', `macos-v${mac}`), mac);
  assert.equal(validateReleaseTag('windows', `windows-v${win}`), win);
  assert.throws(() => validateReleaseTag('macos', `windows-v${win}`));
  assert.throws(() => validateReleaseTag('windows', `macos-v${mac}`));
});
test('legacy, malformed and mismatched tags cannot start a new platform release', () => {
  for (const tag of ['v0.1.0', 'windows-v01.1.0', 'windows-v0.1', 'windows-v0.1.0-malicious', 'windows-v999.0.0']) {
    assert.throws(() => validateReleaseTag('windows', tag));
  }
  assert.throws(() => validateReleaseTag('linux', 'linux-v0.1.0'));
});
test('release workflows listen only to their own tag namespace', () => {
  const mac = fs.readFileSync('.github/workflows/release.yml', 'utf8');
  const win = fs.readFileSync('.github/workflows/windows.yml', 'utf8');
  assert.match(mac, /tags:\s*\n\s*- "macos-v\*"/);
  assert.match(win, /tags:\s*\n\s*- "windows-v\*"/);
  assert.doesNotMatch(mac, /- "v\*"/);
  assert.match(win, /--prerelease --latest=false/);
});
