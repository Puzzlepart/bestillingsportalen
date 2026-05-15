require('@rushstack/eslint-config/patch/modern-module-resolution');

module.exports = {
  extends: ['@microsoft/eslint-config-spfx/lib/profiles/react', 'prettier'],
  parserOptions: { tsconfigRootDir: __dirname },
  plugins: ['prettier', 'unused-imports'],
  rules: {
    'prettier/prettier': 'error',
    'unused-imports/no-unused-imports': 'error',
    'jsx-quotes': ['error', 'prefer-single'],
    quotes: ['error', 'single', { avoidEscape: true, allowTemplateLiterals: true }],
    semi: ['error', 'never'],
    'no-console': 1,
    eqeqeq: 1,
    'require-await': 1,
    '@typescript-eslint/no-explicit-any': 0,
    '@typescript-eslint/explicit-function-return-type': 0,
    '@typescript-eslint/explicit-module-boundary-types': 0,
    '@typescript-eslint/no-inferrable-types': 0,
    '@typescript-eslint/interface-name-prefix': 0,
    '@typescript-eslint/member-delimiter-style': 0,
    'react/prop-types': 0,
    'react/display-name': 0
  },
  overrides: [
    {
      files: ['*.ts', '*.tsx'],
      parser: '@typescript-eslint/parser',
      parserOptions: {
        project: './tsconfig.json',
        ecmaVersion: 2018,
        sourceType: 'module'
      },
      rules: {
        '@rushstack/hoist-jest-mock': 1,
        '@rushstack/import-requires-chunk-name': 1,
        '@rushstack/pair-react-dom-render-unmount': 1
      }
    }
  ]
};
