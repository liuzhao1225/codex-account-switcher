import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { validateReleaseTag } from '../validate-release-tag.mjs';

test('one tag must match all three build version sources', () => {
  const version = fs.readFileSync('Sources/SwitcherCore/Models.swift', 'utf8')
    .match(/public static let current = "([^"]+)"/)[1];
  assert.equal(validateReleaseTag(`v${version}`), version);
  for (const tag of [`macos-v${version}`, `windows-v${version}`, 'v01.1.0', 'v0.1', 'v0.1.0-rc1', 'v999.0.0']) {
    assert.throws(() => validateReleaseTag(tag));
  }
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'switcher-version-'));
  try {
    for (const file of ['Sources/SwitcherCore/Models.swift', 'scripts/package-local-app.sh', 'windows/Directory.Build.props']) {
      fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
      fs.copyFileSync(file, path.join(root, file));
    }
    const props = path.join(root, 'windows/Directory.Build.props');
    fs.writeFileSync(props, fs.readFileSync(props, 'utf8').replace(`<Version>${version}</Version>`, '<Version>999.0.0</Version>'));
    assert.throws(() => validateReleaseTag(`v${version}`, root), /unified version sources/);
  } finally { fs.rmSync(root, { recursive: true }); }
});

test('the fork release publishes verified macOS and Windows artifacts from one tag', () => {
  const release = fs.readFileSync('.github/workflows/release.yml', 'utf8');
  const windows = fs.readFileSync('.github/workflows/windows.yml', 'utf8');
  assert.match(release, /tags:\s*\n\s*- "v\*"/);
  assert.match(release, /needs: \[macos, windows\]/);
  assert.match(release, /uses: \.\/\.github\/workflows\/windows\.yml/);
  assert.match(release, /CODESIGN_IDENTITY: "-"/);
  assert.match(release, /shasum -a 256 --check "\$DMG_NAME\.sha256" "\$EXE_NAME\.sha256"/);
  assert.match(release, /gh release create [\s\S]*--verify-tag/);
  assert.doesNotMatch(release, /secrets\.|notarytool/);
  assert.match(windows, /workflow_call:/);
  assert.doesNotMatch(windows, /gh release create|tags:/);
});
