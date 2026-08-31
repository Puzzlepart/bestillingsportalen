const spfxProfile = require('@microsoft/eslint-config-spfx/lib/flat-profiles/react')
const prettierConfig = require('eslint-config-prettier')
const prettierPlugin = require('eslint-plugin-prettier')
const unusedImports = require('eslint-plugin-unused-imports')

module.exports = [
  ...spfxProfile,
  prettierConfig,
  {
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: {
      parserOptions: {
        tsconfigRootDir: __dirname,
        project: './tsconfig.json'
      }
    },
    plugins: {
      prettier: prettierPlugin,
      'unused-imports': unusedImports
    },
    rules: {
      'prettier/prettier': 'error',
      'unused-imports/no-unused-imports': 'error',
      'jsx-quotes': ['error', 'prefer-single'],
      quotes: ['error', 'single', { avoidEscape: true, allowTemplateLiterals: true }],
      semi: ['error', 'never'],
      'no-console': 1,
      // The SPFx profile enables @typescript-eslint/no-floating-promises, whose
      // sanctioned opt-out for fire-and-forget calls is the `void` operator —
      // so `void` must stay legal in statement position.
      'no-void': [1, { allowAsStatement: true }],
      eqeqeq: 1,
      'require-await': 1,
      '@typescript-eslint/no-explicit-any': 0,
      '@typescript-eslint/explicit-function-return-type': 0,
      '@typescript-eslint/explicit-module-boundary-types': 0,
      '@typescript-eslint/no-inferrable-types': 0,
      'react/prop-types': 0,
      'react/display-name': 0
    }
  }
]
