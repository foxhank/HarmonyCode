// Reads the test account file (provider key, base URLs, model). The key is never printed.
import * as fs from 'fs';

export interface TestAccount {
  key: string;
  openaiBase: string;
  anthropicBase: string;
  model: string;
}

function field(text: string, re: RegExp): string {
  const m = text.match(re);
  return m === null ? '' : m[1];
}

export function readTestAccount(path: string): TestAccount {
  const text = fs.readFileSync(path, 'utf-8');
  const acct: TestAccount = {
    key: field(text, /(sk-[A-Za-z0-9_-]+)/),
    openaiBase: field(text, /base_url \(OpenAI\)\s+(\S+)/),
    anthropicBase: field(text, /base_url \(Anthropic\)\s+(\S+)/),
    model: field(text, /model_name\s+(\S+)/)
  };
  if (!acct.key || !acct.openaiBase || !acct.model) {
    throw new Error('test account file is missing the key, base_url or model_name');
  }
  return acct;
}
