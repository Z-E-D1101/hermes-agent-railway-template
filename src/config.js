import fs from "node:fs";
import path from "node:path";
import yaml from "yaml";
import {
  CONFIG_API_KEY_KEY,
  CONFIG_BASE_URL_KEY,
  CONFIG_MODEL_KEY,
  CONFIG_PROVIDER_KEY,
  HERMES_HOME,
} from "./constants.js";
import { ensureEnvFile } from "./env.js";

export const CONFIG_FILE = path.join(HERMES_HOME, "config.yaml");

export function ensureConfigFile() {
  ensureEnvFile();
  if (!fs.existsSync(CONFIG_FILE)) {
    const example = "/opt/hermes/cli-config.yaml.example";
    if (fs.existsSync(example)) {
      fs.copyFileSync(example, CONFIG_FILE);
    } else {
      fs.writeFileSync(CONFIG_FILE, "model:\n  default: anthropic/claude-opus-4.6\n", "utf8");
    }
  }
}

export function loadConfigDoc() {
  ensureConfigFile();
  const raw = fs.readFileSync(CONFIG_FILE, "utf8");
  return yaml.parse(raw) ?? {};
}

export function getDefaultModel() {
  const doc = loadConfigDoc();
  return doc?.model?.default ?? "";
}

function ensureModelSection(doc) {
  if (!doc.model || typeof doc.model !== "object") {
    doc.model = {};
  }
}

export function setDefaultModel(model) {
  ensureConfigFile();
  const doc = loadConfigDoc();
  ensureModelSection(doc);
  doc.model.default = model;
  fs.writeFileSync(CONFIG_FILE, yaml.stringify(doc), "utf8");
}

export function setModelConfig(updates) {
  ensureConfigFile();
  const doc = loadConfigDoc();
  ensureModelSection(doc);
  if (updates.provider) doc.model.provider = updates.provider;
  if (updates.baseUrl) doc.model.base_url = updates.baseUrl;
  if (updates.apiKey) doc.model.api_key = updates.apiKey;
  if (updates.model) doc.model.default = updates.model;
  fs.writeFileSync(CONFIG_FILE, yaml.stringify(doc), "utf8");
}

export function getModelUiConfig() {
  const doc = loadConfigDoc();
  const model = doc?.model ?? {};
  const apiKey = model.api_key ?? "";
  return {
    [CONFIG_MODEL_KEY]: {
      value: model.default ?? "",
      masked: model.default ?? "",
      set: Boolean(model.default && String(model.default).trim()),
      from: "config",
    },
    [CONFIG_PROVIDER_KEY]: {
      value: model.provider ?? "",
      masked: model.provider ?? "",
      set: Boolean(model.provider && String(model.provider).trim()),
      from: "config",
    },
    [CONFIG_BASE_URL_KEY]: {
      value: model.base_url ?? "",
      masked: model.base_url ?? "",
      set: Boolean(model.base_url && String(model.base_url).trim()),
      from: "config",
    },
    [CONFIG_API_KEY_KEY]: {
      value: "",
      masked: apiKey ? `${String(apiKey).slice(0, 3)}***${String(apiKey).slice(-3)}` : "",
      set: Boolean(apiKey && String(apiKey).trim()),
      from: "config",
    },
  };
}
