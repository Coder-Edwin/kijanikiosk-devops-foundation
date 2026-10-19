'use strict';

// ESLint flat config. Rules are listed explicitly so the standard is visible in review.
const nodeGlobals = {
  require: 'readonly', module: 'writable', exports: 'writable', process: 'readonly',
  console: 'readonly', __dirname: 'readonly', Buffer: 'readonly', setTimeout: 'readonly', fetch: 'readonly',
};

module.exports = [
  { ignores: ['node_modules/', 'dist/', 'reports/'] },
  {
    files: ['**/*.js'],
    languageOptions: { ecmaVersion: 2023, sourceType: 'commonjs', globals: nodeGlobals },
    rules: {
      'no-undef': 'error',
      'no-unused-vars': 'error',
      'no-unreachable': 'error',
      'no-dupe-keys': 'error',
      'no-var': 'error',
      'prefer-const': 'error',
      eqeqeq: ['error', 'always'],
      strict: ['error', 'global'],
      'no-console': ['error', { allow: ['error'] }],
    },
  },
  {
    files: ['scripts/**/*.js', 'src/server.js'],
    rules: { 'no-console': 'off' },
  },
];
