'use strict';

/**
 * OpenAI API-equivalent pricing in USD per million tokens.
 *
 * Snapshot: OpenAI API pricing pages, checked 2026-09-11. Codex subscriptions
 * are not billed per token in the CLI, so all costs shown by this project are
 * estimates of what the same usage would cost on the pay-as-you-go API.
 */

const MODELS = [
  { key: 'gpt-6-astra', name: 'GPT-6 Astra', input: 10, cachedInput: 1, output: 50 },
  { key: 'gpt-5.6-luna', name: 'GPT-5.6 Luna', input: 0.2, cachedInput: 0.02, output: 1.2 },
  { key: 'gpt-5.6-terra', name: 'GPT-5.6 Terra', input: 2, cachedInput: 0.2, output: 12 },
  { key: 'gpt-5.6-sol', name: 'GPT-5.6 Sol', input: 4, cachedInput: 0.4, output: 20 },
  { key: 'gpt-5.6', name: 'GPT-5.6 Sol', input: 4, cachedInput: 0.4, output: 20 },
  { key: 'gpt-5.5-pro', name: 'GPT-5.5 Pro', input: 30, cachedInput: null, output: 180 },
  { key: 'gpt-5.5', name: 'GPT-5.5', input: 5, cachedInput: 0.5, output: 30 },
  { key: 'gpt-5.4-mini', name: 'GPT-5.4 mini', input: 0.75, cachedInput: 0.075, output: 4.5 },
  { key: 'gpt-5.4-nano', name: 'GPT-5.4 nano', input: 0.2, cachedInput: 0.02, output: 1.25 },
  { key: 'gpt-5.4-pro', name: 'GPT-5.4 Pro', input: 30, cachedInput: null, output: 180 },
  { key: 'gpt-5.4', name: 'GPT-5.4', input: 2.5, cachedInput: 0.25, output: 15 },
  { key: 'gpt-5.3', name: 'GPT-5.3', input: 1.75, cachedInput: 0.175, output: 14 },
  { key: 'gpt-5-mini', name: 'GPT-5 mini', input: 0.25, cachedInput: 0.025, output: 2 },
  { key: 'gpt-5-nano', name: 'GPT-5 nano', input: 0.05, cachedInput: 0.005, output: 0.4 },
  { key: 'gpt-5', name: 'GPT-5', input: 1.25, cachedInput: 0.125, output: 10 },
  { key: 'gpt-4.1-mini', name: 'GPT-4.1 mini', input: 0.4, cachedInput: 0.1, output: 1.6 },
  { key: 'gpt-4.1-nano', name: 'GPT-4.1 nano', input: 0.1, cachedInput: 0.025, output: 0.4 },
  { key: 'gpt-4.1', name: 'GPT-4.1', input: 2, cachedInput: 0.5, output: 8 },
  { key: 'o4-mini', name: 'o4-mini', input: 1.1, cachedInput: 0.275, output: 4.4 },
  { key: 'o3-pro', name: 'o3-pro', input: 20, cachedInput: null, output: 80 },
  { key: 'o3-mini', name: 'o3-mini', input: 1.1, cachedInput: 0.55, output: 4.4 },
  { key: 'o3', name: 'o3', input: 2, cachedInput: 0.5, output: 8 },
];

function normalizeModelId(modelId) {
  if (typeof modelId !== 'string') return null;
  const id = modelId
    .toLowerCase()
    .replace(/\[[^\]]*\]/g, '')
    .replace(/[_:]/g, '-')
    .trim();
  return id || null;
}

function modelInfo(modelId) {
  const id = normalizeModelId(modelId);
  if (!id) return null;
  for (const model of MODELS) {
    if (id.includes(model.key)) return { ...model };
  }
  return null;
}

function modelDisplayName(modelId) {
  const info = modelInfo(modelId);
  if (info) return info.name;
  if (typeof modelId !== 'string' || !modelId.trim()) return null;
  return modelId.trim();
}

function costForUsage(modelId, usage) {
  const info = modelInfo(modelId);
  if (!info || !usage || typeof usage !== 'object') return null;

  const input = toNum(usage.inputTokens);
  const cached = Math.min(input, Math.max(0, toNum(usage.cachedInputTokens)));
  const uncached = Math.max(0, input - cached);
  const cachedRate = info.cachedInput == null ? info.input : info.cachedInput;
  const usd = (
    uncached * info.input
    + cached * cachedRate
    + toNum(usage.outputTokens) * info.output
  ) / 1_000_000;

  return Number.isFinite(usd) ? usd : null;
}

function sessionCost(models) {
  if (!models || typeof models !== 'object') return null;

  let usd = 0;
  let complete = true;
  let any = false;
  const perModel = [];

  for (const [modelId, usage] of Object.entries(models)) {
    if (!hasUsage(usage)) continue;
    any = true;

    const cost = costForUsage(modelId, usage);
    if (cost == null) {
      complete = false;
      continue;
    }

    usd += cost;
    perModel.push({ modelId, name: modelDisplayName(modelId), usd: cost });
  }

  if (!any) return null;
  perModel.sort((a, b) => b.usd - a.usd);
  return { usd, complete, perModel };
}

function hasUsage(usage) {
  return toNum(usage && usage.inputTokens) > 0
    || toNum(usage && usage.cachedInputTokens) > 0
    || toNum(usage && usage.outputTokens) > 0
    || toNum(usage && usage.reasoningOutputTokens) > 0
    || toNum(usage && usage.totalTokens) > 0;
}

function toNum(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

module.exports = {
  MODELS,
  costForUsage,
  modelDisplayName,
  modelInfo,
  normalizeModelId,
  sessionCost,
};
