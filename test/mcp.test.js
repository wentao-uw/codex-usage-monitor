'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');

const {
  UI_URI,
  dispatch,
  textSummary,
  toUiData,
  usageTool,
} = require('../mcp/server');
const { summarizeSessionFile } = require('../lib/session');

const fixture = path.join(__dirname, 'fixtures', 'session-basic.jsonl');
const serverPath = path.join(__dirname, '..', 'mcp', 'server.js');

test('MCP tool is read-only and linked to the usage card', () => {
  const tool = usageTool();
  assert.equal(tool.name, 'show_usage');
  assert.equal(tool.annotations.readOnlyHint, true);
  assert.equal(tool._meta.ui.resourceUri, UI_URI);
  assert.equal(tool._meta['openai/outputTemplate'], UI_URI);
});

test('MCP resource returns a self-contained app card', async () => {
  const result = await dispatch('resources/read', { uri: UI_URI });
  assert.equal(result.contents[0].mimeType, 'text/html;profile=mcp-app');
  assert.match(result.contents[0].text, /Codex usage/);
  assert.match(result.contents[0].text, /ui\/notifications\/tool-result/);
  assert.match(result.contents[0].text, /tools\/call/);
});

test('summary converts into serializable UI data and text fallback', async () => {
  const summary = await summarizeSessionFile(fixture);
  const data = toUiData(summary);
  assert.equal(data.status, 'ok');
  assert.equal(data.totalUsage.totalTokens, 2500);
  assert.equal(data.session.model, 'gpt-5.4-mini');
  assert.equal(typeof JSON.stringify(data), 'string');
  assert.match(textSummary(data), /2,500 total tokens/);
});

test('show_usage reads the latest session from CODEX_HOME', async () => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-usage-mcp-'));
  const sessionDir = path.join(codexHome, 'sessions', '2026', '06', '30');
  fs.mkdirSync(sessionDir, { recursive: true });
  fs.copyFileSync(fixture, path.join(sessionDir, 'rollout-test.jsonl'));
  const previous = process.env.CODEX_HOME;
  process.env.CODEX_HOME = codexHome;
  try {
    const result = await dispatch('tools/call', { name: 'show_usage', arguments: {} });
    assert.equal(result.structuredContent.totalUsage.totalTokens, 2500);
    assert.equal(result.isError, false);
  } finally {
    if (previous === undefined) delete process.env.CODEX_HOME;
    else process.env.CODEX_HOME = previous;
  }
});

test('stdio transport flushes an async tool result before input closes', () => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), 'codex-usage-stdio-'));
  const sessionDir = path.join(codexHome, 'sessions', '2026', '06', '30');
  fs.mkdirSync(sessionDir, { recursive: true });
  fs.copyFileSync(fixture, path.join(sessionDir, 'rollout-test.jsonl'));
  const messages = [
    { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18' } },
    { jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'show_usage', arguments: {} } },
  ];
  const result = spawnSync(process.execPath, [serverPath], {
    input: `${messages.map(JSON.stringify).join('\n')}\n`,
    encoding: 'utf8',
    env: { ...process.env, CODEX_HOME: codexHome },
  });

  assert.equal(result.status, 0);
  const responses = result.stdout.trim().split('\n').map(JSON.parse);
  assert.equal(responses.length, 2);
  assert.equal(responses.find((item) => item.id === 2).result.structuredContent.totalUsage.totalTokens, 2500);
});
