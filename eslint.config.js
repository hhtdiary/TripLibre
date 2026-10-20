import js from '@eslint/js';
import globals from 'globals';

export default [
  { ignores: ['node_modules/', '.claude/', '.build-xcode/', 'Packages/**/.build/', 'analysis/.venv/', '.vercel/'] },
  js.configs.recommended,
  {
    rules: {
      eqeqeq: ['error', 'smart'],
      'prefer-const': 'error',
      'no-var': 'error',
      // `catch (e) {}` is the house idiom for best-effort localStorage / clipboard calls.
      'no-empty': ['error', { allowEmptyCatch: true }],
      'no-unused-vars': ['error', { caughtErrors: 'none' }],
    },
  },
  {
    files: ['docs/**/*.js'],
    languageOptions: { sourceType: 'script', globals: globals.browser },
  },
  {
    files: ['*.js', 'scripts/**/*.js'],
    languageOptions: { globals: globals.node },
  },
];
