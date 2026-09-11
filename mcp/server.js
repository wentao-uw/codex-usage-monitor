#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const {
  defaultCodexHome,
  findLatestSessionFile,
  summarizeSessionFile,
} = require('../lib/session');

const SERVER_NAME = 'codex-usage-monitor';
const SERVER_VERSION = '0.1.0';
const UI_URI = 'ui://codex-usage-monitor/usage-card-v1.html';
const UI_PATH = path.join(__dirname, '..', 'ui', 'usage-card.html');

let inputBuffer = '';
let inputEnded = false;
let activeRequests = 0;

function start() {
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => {
    inputBuffer += chunk;
    drainInput();
  });
  process.stdin.on('end', () => {
    inputEnded = true;
    maybeExit();
  });
  process.stdin.on('error', () => {
    inputEnded = true;
    maybeExit();
  });
}

function drainInput() {
  while (true) {
    const newline = inputBuffer.indexOf('\n');
    if (newline === -1) return;
    const line = inputBuffer.slice(0, newline).trim();
    inputBuffer = inputBuffer.slice(newline + 1);
    if (!line) continue;

    let message;
    try {
      message = JSON.parse(line);
    } catch {
      continue;
    }
    void handleMessage(message);
  }
}

async function handleMessage(message) {
  if (!message || message.jsonrpc !== '2.0' || !message.method) return;
  if (message.id === undefined || message.id === null) return;

  activeRequests++;
  try {
    const result = await dispatch(message.method, message.params || {});
    send({ jsonrpc: '2.0', id: message.id, result });
  } catch (error) {
    send({
      jsonrpc: '2.0',
      id: message.id,
      error: {
        code: error && error.code ? error.code : -32603,
        message: error && error.message ? error.message : 'Internal error',
      },
    });
  } finally {
    activeRequests--;
    maybeExit();
  }
}

function maybeExit() {
  if (inputEnded && activeRequests === 0) process.exit(0);
}

async function dispatch(method, params) {
  switch (method) {
    case 'initialize':
      return {
        protocolVersion: params.protocolVersion || '2025-06-18',
        capabilities: { tools: {}, resources: {} },
        serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
      };
    case 'ping':
      return {};
    case 'tools/list':
      return { tools: [usageTool()] };
    case 'tools/call':
      if (params.name !== 'show_usage') throw rpcError(-32601, `Unknown tool: ${params.name}`);
      return showUsage();
    case 'resources/list':
      return {
        resources: [{
          uri: UI_URI,
          name: 'Codex usage dashboard',
          title: 'Codex Usage Dashboard',
          description: 'Interactive token, context, cache, rate-limit, and cost dashboard.',
          mimeType: 'text/html;profile=mcp-app',
        }],
      };
    case 'resources/templates/list':
      return { resourceTemplates: [] };
    case 'resources/read':
      if (params.uri !== UI_URI) throw rpcError(-32002, `Resource not found: ${params.uri}`);
      return {
        contents: [{
          uri: UI_URI,
          mimeType: 'text/html;profile=mcp-app',
          text: fs.readFileSync(UI_PATH, 'utf8'),
          _meta: {
            ui: {
              prefersBorder: true,
              csp: { connectDomains: [], resourceDomains: [] },
            },
          },
        }],
      };
    default:
      throw rpcError(-32601, `Method not found: ${method}`);
  }
}

function usageTool() {
  return {
    name: 'show_usage',
    title: 'Show Codex usage',
    description: 'Read the latest local Codex session and display an interactive usage dashboard. Use whenever the user asks for Codex token usage, context usage, cache rate, rolling limits, or estimated cost.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    annotations: {
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
    },
    _meta: {
      ui: { resourceUri: UI_URI },
      'openai/outputTemplate': UI_URI,
      'openai/toolInvocation/invoking': 'Reading Codex usage…',
      'openai/toolInvocation/invoked': 'Codex usage ready',
    },
  };
}

async function showUsage() {
  const transcriptPath = findLatestSessionFile(defaultCodexHome());
  const summary = await summarizeSessionFile(transcriptPath);

  if (!summary) {
    const structuredContent = {
      status: 'empty',
      message: 'No local Codex session was found.',
      generatedAt: new Date().toISOString(),
    };
    return {
      structuredContent,
      content: [{ type: 'text', text: structuredContent.message }],
      isError: false,
    };
  }

  const structuredContent = toUiData(summary);
  return {
    structuredContent,
    content: [{ type: 'text', text: textSummary(structuredContent) }],
    isError: false,
  };
}

function toUiData(summary) {
  return {
    status: 'ok',
    generatedAt: new Date().toISOString(),
    latestAt: iso(summary.latestAt),
    session: {
      id: summary.sessionId,
      model: summary.model,
      modelName: summary.modelName,
      reasoningEffort: summary.reasoningEffort,
      planType: summary.planType,
      turnCount: summary.turnCount,
    },
    context: {
      usedTokens: summary.latestUsage.inputTokens,
      windowTokens: summary.contextWindow,
      usedPercent: summary.contextUsedPercent,
    },
    latestUsage: copyUsage(summary.latestUsage),
    totalUsage: copyUsage(summary.totalUsage),
    limits: [summary.rateLimits.primary, summary.rateLimits.secondary]
      .filter(Boolean)
      .map((limit) => ({
        label: limit.label,
        usedPercent: limit.usedPercent,
        remainingPercent: Math.max(0, 100 - Number(limit.usedPercent || 0)),
        windowMinutes: limit.windowMinutes,
        resetsAt: limit.resetsAt ? new Date(limit.resetsAt * 1000).toISOString() : null,
      })),
    cost: summary.cost ? {
      usd: summary.cost.usd,
      complete: summary.cost.complete,
      perModel: summary.cost.perModel,
    } : null,
  };
}

function copyUsage(usage) {
  return {
    inputTokens: usage.inputTokens,
    cachedInputTokens: usage.cachedInputTokens,
    outputTokens: usage.outputTokens,
    reasoningOutputTokens: usage.reasoningOutputTokens,
    totalTokens: usage.totalTokens,
    cacheHitPercent: usage.cacheHitPercent,
  };
}

function textSummary(data) {
  const usage = data.totalUsage;
  const context = data.context;
  const limits = data.limits.length
    ? data.limits.map((limit) => `${limit.label} ${limit.usedPercent}% used`).join(', ')
    : 'limits unavailable';
  const cost = data.cost ? `, API-equivalent cost $${data.cost.usd.toFixed(4)}` : '';
  return `Codex usage: ${usage.totalTokens.toLocaleString('en-US')} total tokens (${usage.inputTokens.toLocaleString('en-US')} input, ${usage.outputTokens.toLocaleString('en-US')} output), context ${context.usedPercent ?? 0}% used, cache ${usage.cacheHitPercent ?? 0}%, ${limits}${cost}.`;
}

function iso(value) {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

function rpcError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

if (require.main === module) start();

module.exports = {
  UI_URI,
  dispatch,
  start,
  textSummary,
  toUiData,
  usageTool,
};
