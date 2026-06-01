const js = require('@eslint/js');

// Globals available to all JS files (Node CommonJS).
const nodeGlobals = {
  process: 'readonly',
  console: 'readonly',
  module: 'writable',
  require: 'readonly',
  __dirname: 'readonly',
  __filename: 'readonly',
  Buffer: 'readonly',
  setTimeout: 'readonly',
  setInterval: 'readonly',
  clearTimeout: 'readonly',
  clearInterval: 'readonly',
};

// Extra globals only meaningful inside test files (node:test runner).
const nodeTestGlobals = {
  test: 'readonly',
  describe: 'readonly',
  it: 'readonly',
  before: 'readonly',
  after: 'readonly',
  beforeEach: 'readonly',
  afterEach: 'readonly',
  assert: 'readonly',
};

module.exports = [
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'commonjs',
      globals: nodeGlobals,
    },
    rules: {
      'no-unused-vars': 'error',
      'no-console': 'off',
    },
  },
  {
    files: ['test/**/*.js'],
    languageOptions: {
      globals: { ...nodeGlobals, ...nodeTestGlobals },
    },
  },
];
