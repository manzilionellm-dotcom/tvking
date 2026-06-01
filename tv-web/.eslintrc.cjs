// =========================================================
//  .eslintrc.cjs — Regles de lint
// =========================================================
//  Strict TypeScript + hooks React. On utilise CJS pour le config
//  parce que eslint ne supporte pas encore le ESM config a 100% en
//  multi-versions Node.
// =========================================================

module.exports = {
  root: true,
  env: { browser: true, es2020: true, node: true },
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'plugin:react-hooks/recommended',
  ],
  ignorePatterns: ['dist', '.eslintrc.cjs', 'node_modules'],
  parser: '@typescript-eslint/parser',
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
  },
  plugins: ['react-refresh'],
  rules: {
    'react-refresh/only-export-components': [
      'warn',
      { allowConstantExport: true },
    ],
    '@typescript-eslint/no-unused-vars': [
      'error',
      { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
    ],
    // Pas de console.log en prod — on a un logger maison (a venir).
    'no-console': ['warn', { allow: ['warn', 'error'] }],
  },
};
