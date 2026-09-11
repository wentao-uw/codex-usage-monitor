'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  costForUsage,
  modelDisplayName,
  modelInfo,
  sessionCost,
} = require('../lib/pricing');

test('resolves current Codex model slugs to friendly names', () => {
  assert.equal(modelDisplayName('gpt-5.6-sol'), 'GPT-5.6 Sol');
  assert.equal(modelDisplayName('gpt-5.6-terra'), 'GPT-5.6 Terra');
  assert.equal(modelDisplayName('gpt-5.6-luna'), 'GPT-5.6 Luna');
  assert.equal(modelDisplayName('gpt-5.5'), 'GPT-5.5');
  assert.equal(modelDisplayName('openai/gpt-5.4-mini-2026-06-01'), 'GPT-5.4 mini');
  assert.equal(modelDisplayName('gpt-5.4-nano'), 'GPT-5.4 nano');
  assert.equal(modelInfo('unknown-model'), null);
});

test('uses the current GPT-5.6 family rates', () => {
  assert.equal(costForUsage('gpt-5.6-sol', {
    inputTokens: 1_000_000,
    cachedInputTokens: 0,
    outputTokens: 100_000,
  }), 6);
  assert.equal(costForUsage('gpt-5.6-terra', {
    inputTokens: 1_000_000,
    cachedInputTokens: 0,
    outputTokens: 100_000,
  }), 3.2);
  assert.equal(costForUsage('gpt-5.6-luna', {
    inputTokens: 1_000_000,
    cachedInputTokens: 0,
    outputTokens: 100_000,
  }), 0.32);
});

test('prices cached input at cached-input rate and output at output rate', () => {
  const usd = costForUsage('gpt-5.5', {
    inputTokens: 1_000_000,
    cachedInputTokens: 250_000,
    outputTokens: 100_000,
  });

  assert.equal(usd, 6.875);
});

test('sessionCost reports per-model totals and incomplete pricing for unknown models', () => {
  const result = sessionCost({
    'gpt-5.5': {
      inputTokens: 1000,
      cachedInputTokens: 300,
      outputTokens: 100,
      reasoningOutputTokens: 40,
    },
    'gpt-5.4-mini': {
      inputTokens: 1200,
      cachedInputTokens: 600,
      outputTokens: 200,
      reasoningOutputTokens: 110,
    },
    'future-model': {
      inputTokens: 10,
      cachedInputTokens: 0,
      outputTokens: 5,
      reasoningOutputTokens: 0,
    },
  });

  assert.equal(result.complete, false);
  assert.equal(result.perModel.length, 2);
  assert.equal(result.perModel[0].name, 'GPT-5.5');
  assert.ok(result.usd > 0);
});
